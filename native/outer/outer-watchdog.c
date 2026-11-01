/* GT8 Pro finite registration experiment lifecycle helper, 2026-10-23.
 * SPDX-License-Identifier: Apache-2.0
 * Only launches one fixed launcher/server pair; never accepts a PID to signal.
 * A separate bounded guardian retains a pidfd to this exact child across exec.
 */
#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/syscall.h>
#include <time.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lease-decision.h"

#ifndef GT8_ROOT
#define GT8_ROOT "/data/adb/gt8pro-mosey-service"
#endif
#ifndef GT8_LAUNCHER
#define GT8_LAUNCHER "/data/adb/ksu/bin/busybox"
#endif
#ifndef GT8_SERVER
#define GT8_SERVER "/odm/bin/mosey_server"
#endif
#ifndef GT8_BUDGET
#define GT8_BUDGET 40
#endif
#define LOG_LIMIT (1024*1024)
#ifndef SYS_pidfd_open
#define SYS_pidfd_open 434
#endif
#ifndef SYS_pidfd_send_signal
#define SYS_pidfd_send_signal 424
#endif
#ifndef SYS_close_range
#define SYS_close_range 436
#endif

static void decimal(char *out,unsigned long long value) {
    char reverse[32];size_t n=0;
    do {reverse[n++]=(char)('0'+value%10);value/=10;}while(value);
    for(size_t i=0;i<n;i++) out[i]=reverse[n-1-i];
    out[n]=0;
}

static int owned_directory(int fd) {
    struct stat st;
    return fd>=0 && !fstat(fd,&st) && S_ISDIR(st.st_mode) &&
        st.st_uid==getuid() && (st.st_mode&0777)==0700;
}
static int write_all(int fd,const void *data,size_t length) {
    const char *p=data;
    while(length) {
        ssize_t n=write(fd,p,length);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) return -1;
        p+=n; length-=(size_t)n;
    }
    return 0;
}
static int put(int dir,const char *name,const char *value) {
    int fd=openat(dir,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0) return -1;
    int rc=write_all(fd,value,strlen(value));
    if(close(fd)) rc=-1;
    return rc;
}
static int text_at(int dir,const char *name,char *buf,size_t size,int private_file) {
    int fd=openat(dir,name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
    if(fd<0) return -1;
    struct stat st;
    if(fstat(fd,&st) || !S_ISREG(st.st_mode) ||
       (private_file && (st.st_uid!=getuid() || (st.st_mode&0777)!=0600))) {close(fd);return -1;}
    size_t used=0;
    for(;;) {
        ssize_t n=read(fd,buf+used,size-1-used);
        if(n<0 && errno==EINTR) continue;
        if(n<0 || (n>0 && used+(size_t)n==size-1)) {close(fd);return -1;}
        if(!n) break;
        used+=(size_t)n;
    }
    close(fd);buf[used]=0;
    return (int)used;
}
static int run_name(const char *name) {
    if(strlen(name)!=10 || strncmp(name,"run.",4)) return 0;
    for(const char *p=name+4;*p;p++)
        if(!((*p>='a'&&*p<='z')||(*p>='A'&&*p<='Z')||(*p>='0'&&*p<='9'))) return 0;
    return 1;
}
static int open_root(void) {
    int fd=open(GT8_ROOT,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(!owned_directory(fd)) {if(fd>=0)close(fd);return -1;}
    return fd;
}
static int open_run(int root,const char *name) {
    if(!run_name(name)) return -1;
    int fd=openat(root,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(!owned_directory(fd)) {if(fd>=0)close(fd);return -1;}
    return fd;
}
static int caller(void) {
#ifdef GT8_HOST_TEST
    return 1;
#else
    if(getuid()!=0 || geteuid()!=0) return 0;
    char context[128];
    int n=text_at(AT_FDCWD,"/proc/self/attr/current",context,sizeof(context),0);
    if(n<=0) return 0;
    while(n>0 && (context[n-1]=='\n'||context[n-1]==0)) context[--n]=0;
    return !strcmp(context,"u:r:ksu:s0");
#endif
}
static __attribute__((unused)) int private_tree(void) {
#ifdef GT8_HOST_TEST
    return 1;
#else
    char a[128],b[128];
    ssize_t an=readlink("/proc/self/ns/mnt",a,sizeof(a));
    ssize_t bn=readlink("/proc/1/ns/mnt",b,sizeof(b));
    if(an<=0 || bn<=0 || (an==bn&&!memcmp(a,b,(size_t)an))) return 0;
    FILE *f=fopen("/proc/self/mountinfo","re");
    if(!f) return 0;
    char line[8192];int count=0,ok=1;
    while(fgets(line,sizeof(line),f)) {
        if(!strchr(line,'\n') || !strstr(line," - ") || strstr(line," shared:") ||
            strstr(line," master:") || strstr(line," propagate_from:") || ++count>8192) {ok=0;break;}
    }
    if(ferror(f)) ok=0;
    fclose(f);
    return ok&&count>0;
#endif
}
static long long now_ms(void) {
    struct timespec ts;
    if(clock_gettime(CLOCK_BOOTTIME,&ts)) return -1;
    return (long long)ts.tv_sec*1000+ts.tv_nsec/1000000;
}
static int dead(int pidfd,int timeout_ms) {
    struct pollfd p={pidfd,POLLIN,0};
    int rc;
    do {rc=poll(&p,1,timeout_ms);} while(rc<0&&errno==EINTR);
    if(rc<0 || (p.revents&(POLLERR|POLLNVAL))) return -1;
    return rc>0&&(p.revents&(POLLIN|POLLHUP));
}
static int stop_owned(int pidfd) {
    int state=dead(pidfd,0);
    if(state==1) return 0;
    if(state<0) return -1;
    if(syscall(SYS_pidfd_send_signal,pidfd,SIGTERM,NULL,0)<0 && errno!=ESRCH) return -1;
    state=dead(pidfd,2000);
    if(state==1) return 0;
    if(state<0) return -1;
    if(syscall(SYS_pidfd_send_signal,pidfd,SIGKILL,NULL,0)<0 && errno!=ESRCH) return -1;
    return dead(pidfd,3000)==1?0:-1;
}
static int requested(int dir) {
    char b[32];
    return text_at(dir,"outer-stop.request",b,sizeof(b),1)==5 && !strcmp(b,"STOP\n");
}
/* Root-owned, atomic heartbeat: monotonic_ms DRAINED|ACTIVE|UNKNOWN\n.
 * Unknown/stale state can never authorize a normal stop. */
static int lease_snapshot(int dir,long long now, enum gt8_transfer *state) {
    char b[96],word[16],extra; long long stamp;
    int n=text_at(dir,"transfer-heartbeat",b,sizeof(b),1);
    long long after=now_ms();
    if(after<0 || now<0 || after<now) return 0;
    now=after;
    if(n<=0 || sscanf(b,"%lld %15s %c",&stamp,word,&extra)!=2 ||
       stamp<0 || stamp>now || now-stamp>5000) return 0;
    if(!strcmp(word,"DRAINED")) *state=GT8_IDLE;
    else if(!strcmp(word,"ACTIVE")) *state=GT8_ACTIVE;
    else if(!strcmp(word,"UNKNOWN")) *state=GT8_UNKNOWN;
    else return 0;
    return 1;
}
static enum gt8_action lease_stop_action(int dir,long long now) {
    enum gt8_transfer state=GT8_UNKNOWN;
    int fresh=lease_snapshot(dir,now,&state);
    return gt8_lease_decide(1,fresh,1,state);
}
static void guardian(int dir,int daemon_fd,int parent_fd,int owner_fd,int ready_fd) {
    /* No terminal/process-group dependency; still bounded to this one run. */
    if(setsid()<0) _exit(81);
    signal(SIGHUP,SIG_IGN);signal(SIGINT,SIG_IGN);signal(SIGTERM,SIG_IGN);
    long long start=now_ms();
    if(start<0 || write_all(ready_fd,"G",1)) _exit(82);
    close(ready_fd);
    const char *reason="EMERGENCY";
    for(;;) {
        int d=dead(daemon_fd,100),p=dead(parent_fd,0),o=dead(owner_fd,0);
        long long current=now_ms();
        if(d==1) {
            int evidence=put(dir,"outer-guard.reason","CHILD_EXIT\n");
            put(dir,"outer-guard.status",evidence?"UNCONFIRMED\n":"STOPPED\n");
            _exit(evidence?83:0);
        }
        if(d<0 || p!=0 || o!=0 || current<0) break;
        if(current-start>=GT8_BUDGET*1000LL || requested(dir)) {
            enum gt8_action a=lease_stop_action(dir,current);
            /* Normal drain is owned by the inner controller: keep waiting for
             * its namespace cleanup. Only failed liveness is an emergency. */
            if(a==GT8_EMERGENCY) break;
        }
    }
    /* Distinguish a proof-backed stop from parent/heartbeat failure. */
    int evidence=put(dir,"outer-guard.reason",!strcmp(reason,"DRAINED")?"DRAINED\n":"EMERGENCY\n");
    int rc=stop_owned(daemon_fd);
    put(dir,"outer-guard.status",rc||evidence?"UNCONFIRMED\n":"STOPPED\n");
    _exit(rc?83:0);
}
static unsigned long long child_token(pid_t pid) {
    char path[64],buf[4096];
    char number[32];decimal(number,(unsigned long long)pid);
    strcpy(path,"/proc/");strcat(path,number);strcat(path,"/stat");
    if(text_at(AT_FDCWD,path,buf,sizeof(buf),0)<0) return 0;
    char *p=strrchr(buf,')');
    if(!p || p[1]!=' ') return 0;
    p+=2;
    for(int field=3;field<22;field++) {p=strchr(p,' ');if(!p)return 0;p++;}
    char *end;errno=0;
    unsigned long long token=strtoull(p,&end,10);
    return errno||end==p||(*end!=' '&&*end!='\n')?0:token;
}
static int run(int dir,const char *runname,const char *parent_ns,const char *parent_pid) {
    char runpath[256], binddir[280], envbind[300], script[320];
    if(snprintf(runpath,sizeof(runpath),"%s/%s",GT8_ROOT,runname)>=(int)sizeof(runpath) ||
       snprintf(binddir,sizeof(binddir),"%s/binding-code",runpath)>=(int)sizeof(binddir) ||
       snprintf(envbind,sizeof(envbind),"GT8_BINDDIR=%s",binddir)>=(int)sizeof(envbind) ||
       snprintf(script,sizeof(script),"%s/namespace-bind.sh",binddir)>=(int)sizeof(script)) return 70;
    int check=open(binddir,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(!owned_directory(check)) {if(check>=0)close(check);return 70;}
    close(check);
    const char *duration=getenv("GT8_SOAK_SECONDS");
    if(!duration || (strcmp(duration,"10") && strcmp(duration,"70") && strcmp(duration,"240") && strcmp(duration,"600") && strcmp(duration,"1800"))) return 70;
    char envduration[48];if(snprintf(envduration,sizeof(envduration),"GT8_SOAK_SECONDS=%s",duration)>=(int)sizeof(envduration)) return 70;
    int gate[2],output[2],ready[2];
    if(pipe2(gate,O_CLOEXEC)||pipe2(output,O_CLOEXEC)||pipe2(ready,O_CLOEXEC)) return 70;
    /* Ensure the child PID cannot be recycled before pidfd acquisition. */
    struct sigaction sa={0};sa.sa_handler=SIG_DFL;sigemptyset(&sa.sa_mask);
    if(sigaction(SIGCHLD,&sa,NULL)) return 70;
    int logfd=openat(dir,"outer-daemon.log",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(logfd<0) return 70;
    pid_t child=fork();
    if(child<0) return 70;
    if(child==0) {
        close(gate[1]);close(output[0]);close(ready[0]);close(ready[1]);
        char start=0;
        ssize_t n;do {n=read(gate[0],&start,1);}while(n<0&&errno==EINTR);
        if(n!=1||start!='S') _exit(85);
        int nullfd=open("/dev/null",O_RDONLY|O_CLOEXEC);
        if(nullfd<0||dup2(nullfd,0)<0||dup2(output[1],1)<0||dup2(output[1],2)<0) _exit(86);
        if(syscall(SYS_close_range,3,~0U,0)<0) _exit(86);
        char *args[]={GT8_LAUNCHER,"unshare","-m","/system/bin/sh",script,(char*)parent_ns,(char*)parent_pid,runpath,NULL};
        const char *names[]={"ANDROID_ROOT","ANDROID_DATA","ANDROID_ART_ROOT",
            "ANDROID_RUNTIME_ROOT","ANDROID_TZDATA_ROOT","BOOTCLASSPATH",
            "DEX2OATBOOTCLASSPATH","SYSTEMSERVERCLASSPATH","STANDALONE_SYSTEMSERVER_JARS",
            "ASEC_MOUNTPOINT","ANDROID_I18N_ROOT","EXTERNAL_STORAGE",NULL};
        char *env[20]={"PATH=/system/bin:/system/xbin","LC_ALL=C",envbind,envduration};
        size_t e=4;
        for(size_t i=0;names[i];i++) {
            const char *value=getenv(names[i]);
            if(!value) continue;
            if(strlen(value)>65536 || asprintf(&env[e],"%s=%s",names[i],value)<0) _exit(86);
            e++;
        }
        env[e]=NULL;
        execve(GT8_LAUNCHER,args,env);
        _exit(87);
    }
    close(gate[0]);close(output[1]);
    int childfd=(int)syscall(SYS_pidfd_open,child,0);
    int parentfd=(int)syscall(SYS_pidfd_open,getpid(),0);
    int ownerfd=(int)syscall(SYS_pidfd_open,getppid(),0);
    if(childfd<0||parentfd<0||ownerfd<0) {close(gate[1]);waitpid(child,NULL,0);return 71;}
    unsigned long long token=child_token(child);
    char record[128],number[32];decimal(record,(unsigned long long)child);
    strcat(record," ");decimal(number,token);strcat(record,number);strcat(record,"\n");
    if(!token || put(dir,"outer-child.record",record)) {close(gate[1]);waitpid(child,NULL,0);return 72;}
    pid_t guard=fork();
    if(guard<0) {close(gate[1]);waitpid(child,NULL,0);return 73;}
    if(guard==0) {
        close(gate[1]);close(output[0]);close(ready[0]);close(logfd);
        /* Never retains the child's launch gate or the daemon log pipe. */
        guardian(dir,childfd,parentfd,ownerfd,ready[1]);
    }
    close(ready[1]);close(parentfd);close(ownerfd);
    struct pollfd rp={ready[0],POLLIN,0};char ack=0;
    if(poll(&rp,1,2000)<=0 || read(ready[0],&ack,1)!=1 || ack!='G') {
        close(gate[1]);waitpid(child,NULL,0);waitpid(guard,NULL,0);return 74;
    }
    close(ready[0]);
    if(write_all(gate[1],"S",1)) {close(gate[1]);stop_owned(childfd);return 75;}
    close(gate[1]);
    int flags=fcntl(output[0],F_GETFL);
    if(flags<0||fcntl(output[0],F_SETFL,flags|O_NONBLOCK)) {stop_owned(childfd);return 75;}
    long long started=now_ms();size_t stored=0;int truncated=0,log_error=0;
    for(;;) {
        char buf[4096];ssize_t n=read(output[0],buf,sizeof(buf));
        if(n>0) {
            size_t keep=(size_t)n;
            if(keep>LOG_LIMIT-stored) {keep=LOG_LIMIT-stored;truncated=1;}
            if(keep&&write_all(logfd,buf,keep)) log_error=1;
            /* Preserve namespace-bind's allowlisted report for the caller. */
            if(keep&&write_all(STDOUT_FILENO,buf,keep)) log_error=1;
            stored+=keep;
        } else if(n==0) break;
        else if(errno!=EINTR&&errno!=EAGAIN) {log_error=1;stop_owned(childfd);break;}
        if(dead(childfd,0)==1 && n<0) break;
        long long t=now_ms();
        int gs=0;pid_t gr=waitpid(guard,&gs,WNOHANG);
        if(gr==guard) {guard=-1;if(dead(childfd,0)!=1) stop_owned(childfd);}
        if(started<0||t<0) {stop_owned(childfd);break;}
        if(t-started>=(GT8_BUDGET+3)*1000LL && lease_stop_action(dir,t)==GT8_EMERGENCY) {stop_owned(childfd);break;}
        struct pollfd p={output[0],POLLIN,0};poll(&p,1,50);
    }
    /* Retain pidfd even after exit, and independently insist on termination. */
    int stopped=stop_owned(childfd),status=0;
    int reaped=waitpid(child,&status,WNOHANG)==child;
    if(guard>0) waitpid(guard,NULL,0);
    close(output[0]);close(childfd);close(logfd);
    char guard_state[32];
    int guard_ok=text_at(dir,"outer-guard.status",guard_state,sizeof(guard_state),1)>0 && !strcmp(guard_state,"STOPPED\n");
    char state[160];strcpy(state,"CHILD_REAPED=");strcat(state,reaped?"1":"0");
    strcat(state,"\nEXIT_STATUS=");decimal(number,(unsigned int)status);strcat(state,number);
    strcat(state,"\nLOG_TRUNCATED=");strcat(state,truncated?"1\n":"0\n");
    put(dir,"outer-watchdog.details",state);
    /* A cleanly reaped child can still have failed its namespace cleanup. */
    int ok=!stopped&&reaped&&guard_ok&&!truncated&&!log_error&&WIFEXITED(status)&&WEXITSTATUS(status)==0;
    put(dir,"outer-watchdog.status",ok?"STOPPED\n":"UNCONFIRMED\n");
    return ok?0:76;
}
int main(int argc,char **argv) {
    if(!caller()) return 77;
    if(argc==2&&!strcmp(argv[1],"probe")) {
        int self=(int)syscall(SYS_pidfd_open,getpid(),0);
        if(self<0) return 69;
        int rc=(int)syscall(SYS_pidfd_send_signal,self,0,NULL,0);
        close(self);
        if(rc) return 69;
        puts("PIDFD_SELFTEST=PASS");return 0;
    }
    int root=open_root();if(root<0) return 78;
    if(argc==2&&!strcmp(argv[1],"stop")) {
        char current[32];int n=text_at(root,"current",current,sizeof(current),1);
        if(n<=0) return 79;
        if(current[n-1]=='\n') current[--n]=0;
        int dir=open_run(root,current);if(dir<0)return 79;
        if(put(dir,"outer-stop.request","STOP\n") && !requested(dir)) return 79;
        puts("STOP_REQUEST=RECORDED");return 0;
    }
    if(argc!=5||strcmp(argv[1],"run")) return 80;
    char expected_pid[32];decimal(expected_pid,(unsigned long long)getppid());
    if(strcmp(argv[4],expected_pid)) return 80;
    char ns[128];ssize_t n=readlink("/proc/self/ns/mnt",ns,sizeof(ns)-1);
    if(n<=0 || n>=(ssize_t)sizeof(ns)-1) return 80;
    ns[n]=0;if(strcmp(ns,argv[3])) return 80;
    int dir=open_run(root,argv[2]);if(dir<0)return 79;
    return run(dir,argv[2],argv[3],argv[4]);
}
