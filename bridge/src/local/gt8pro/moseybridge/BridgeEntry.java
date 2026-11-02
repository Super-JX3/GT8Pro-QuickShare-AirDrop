package local.gt8pro.moseybridge;

import android.app.Application;
import android.content.Context;
import android.content.Intent;
import android.content.ComponentName;
import android.content.ServiceConnection;
import android.content.pm.ResolveInfo;
import android.content.pm.ApplicationInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.Process;
import android.os.SystemClock;
import android.util.Log;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.callbacks.XC_LoadPackage;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** New local experimental module; does not load or replace the upstream client. */
public final class BridgeEntry implements IXposedHookLoadPackage {
    private static final AtomicBoolean STARTED=new AtomicBoolean();
    @Override public void handleLoadPackage(XC_LoadPackage.LoadPackageParam loaded) {
        if(!"RMX5200".equals(Build.MODEL)
                || !HookLogic.target(loaded.packageName,loaded.processName,Process.myUid(),
                    Build.VERSION.SDK_INT,Build.DISPLAY)
                || !STARTED.compareAndSet(false,true))return;
        final Session s=new Session(loaded.packageName,loaded.classLoader);
        try {
            Method attach=Application.class.getDeclaredMethod("attach",Context.class);
            s.hook(attach,new XC_MethodHook(){
                @Override protected void afterHookedMethod(MethodHookParam call) {
                    if(call.hasThrowable()||call.args==null||call.args.length!=1)return;
                    Object arg=call.args[0];
                    if(arg instanceof Context)s.attach((Context)arg);
                }
            });
            s.emit("SESSION_STARTED","mode="+BuildVariant.MODE);
            s.emit("MODULE_REVISION","value=1107");
            s.emit("SESSION_LIMIT","seconds=86400");
        } catch(Throwable failure){s.emit("SETUP_REJECTED","reason=ATTACH_HOOK");s.stop();}
    }
    private static final class Session {
        final String pkg;
        final ClassLoader loader;
        final long started=SystemClock.elapsedRealtime(), deadline;
        final Object lock=new Object();
        final List<XC_MethodHook.Unhook> handles=new ArrayList<>();
        final AtomicBoolean attached=new AtomicBoolean();
        final AtomicInteger logs=new AtomicInteger();
        final AtomicInteger gmsPrimaryReadLogs=new AtomicInteger();
        final AtomicInteger gmsRegistryLogs=new AtomicInteger();
        final AtomicInteger criticalLogs=new AtomicInteger();
        final ThreadLocal<Boolean> diagnosticLookup=new ThreadLocal<>();
        final AtomicInteger discoverSequence=new AtomicInteger();
        final ThreadLocal<Integer> sendSlot=new ThreadLocal<>();
        final SlotPool sendTasks=new SlotPool(4);
        final SlotPool discoverTasks=new SlotPool(8);
        final Map<Object,Integer> sendCalls=new IdentityHashMap<>();
        final ThreadLocal<Integer> discoverSlot=new ThreadLocal<>();
        final ConcurrentHashMap<Integer,Thread> sendThreads=new ConcurrentHashMap<>();
        final Map<Object,Boolean> tlsObserved=new IdentityHashMap<>();
        final ReceiveCallbackCache receiveCallbacks=new ReceiveCallbackCache();
        final ConcurrentHashMap<Integer,Thread> discoverThreads=new ConcurrentHashMap<>();
        final Set<Class<?>> nativeVersionHooks=Collections.newSetFromMap(new IdentityHashMap<Class<?>,Boolean>());
        final ScheduledExecutorService workers=Executors.newScheduledThreadPool(2,r->{
            Thread t=new Thread(r,"GT8ProBridge");t.setDaemon(true);return t;
        });
        volatile boolean armed, nativeArmed, stopped;
        volatile int gmsUid=-1;
        Session(String p,ClassLoader l){
            pkg=p;loader=l;
            deadline=started+86400000L;
            workers.schedule(()->{emit("SESSION_EXPIRED","hooks=REMOVING");stop();},86400,TimeUnit.SECONDS);
        }
        void hook(Member method,XC_MethodHook callback) throws Exception {
            synchronized(lock){
                if(stopped||SystemClock.elapsedRealtime()>=deadline)throw new Exception("EXPIRED");
                XC_MethodHook.Unhook h=XposedBridge.hookMethod(method,callback);
                if(h==null)throw new Exception("NO_HANDLE");
                handles.add(h);
            }
        }
        boolean active(){return armed&&!stopped&&SystemClock.elapsedRealtime()<deadline;}
        boolean nativeActive(){return nativeArmed&&!stopped&&SystemClock.elapsedRealtime()<deadline;}
        void attach(Context context){
            try {
                ApplicationInfo info=context.getApplicationInfo();
                if(!pkg.equals(context.getPackageName())||info==null||info.uid!=Process.myUid())return;
                if(!attached.compareAndSet(false,true))return;
                try{if("com.google.android.mosey".equals(pkg))gmsUid=context.getPackageManager().getApplicationInfo("com.google.android.gms",0).uid;}catch(Throwable ignored){}
                emit("ATTACH_OBSERVED","result=PASS");
                workers.execute(()->prepare(info));
            }catch(Throwable failure){emit("SETUP_REJECTED","reason=CONTEXT_IDENTITY");stop();}
        }
        void prepare(ApplicationInfo info){
            long preparationDeadline=Math.min(deadline,SystemClock.elapsedRealtime()+15000);
            try {
                boolean gms="com.google.android.gms".equals(pkg);
                emit("PREPARATION_STARTED","kind=OBSERVATION");
                SourceGuard.hash(info,gms?SourceGuard.GMS_SHA:SourceGuard.MOSEY_SHA,preparationDeadline);
                emit("APK_IDENTITY","result=PASS");
                if(gms)installGms(info,preparationDeadline);else installMosey(info,preparationDeadline);
                synchronized(lock){
                    if(stopped||SystemClock.elapsedRealtime()>=deadline)throw new Exception("EXPIRED");
                    armed=true;
                }
                emit("HOOKS_READY","scope="+(gms?"GMS_MAIN":"MOSEY_MAIN"));
                if(!gms){workers.execute(this::probeNative);}
            }catch(Throwable failure){
                // Never print a file path, Throwable message, package arguments or remote data.
                emit("SETUP_REJECTED","reason="+failureReason(failure));stop();
            }
        }
        Class<?> target(String name,ApplicationInfo info,long until)throws Exception{
            SourceGuard.time(until);
            Class<?> c=Class.forName(name,false,loader);
            SourceGuard.owner(c,info,until);
            return c;
        }
        void installGms(ApplicationInfo info,long until)throws Exception{
            Class<?> flags=target("kbfs",info,until);
            Method getter=flags.getDeclaredMethod("V");
            if(getter.getReturnType()!=boolean.class||Modifier.isStatic(getter.getModifiers())
                    ||Modifier.isNative(getter.getModifiers())||Modifier.isAbstract(getter.getModifiers()))
                throw new Exception("GETTER_SIGNATURE");
            hook(getter,new XC_MethodHook(){
                @Override protected void afterHookedMethod(MethodHookParam call){
                    if(!active())return;
                    try {
                        Object value=call.getResult();int args=call.args==null?-1:call.args.length;
                        boolean change;
                        synchronized(lock){
                            change=HookLogic.enable(BuildVariant.GMS,armed&&!stopped,SystemClock.elapsedRealtime(),
                                    deadline,call.hasThrowable(),value,args);
                            if(change)call.setResult(Boolean.TRUE);
                        }
                        if(gmsPrimaryReadLogs.incrementAndGet()<=16)emit("GMS_PRIMARY_READ","original="+(call.hasThrowable()?"THREW":
                                Boolean.TRUE.equals(value)?"TRUE":Boolean.FALSE.equals(value)?"FALSE":"OTHER")
                                +" adjusted="+(change?"YES":"NO"));
                    }catch(Throwable ignored){/* Preserve the application's existing outcome. */}
                }
            });
            Class<?> registry=target("jadd",info,until);
            for(final String name:new String[]{"c","b"}){
                Method method=registry.getDeclaredMethod(name);
                if(method.getReturnType()!=void.class||Modifier.isStatic(method.getModifiers()))
                    throw new Exception("REGISTRY_SIGNATURE");
                hook(method,new XC_MethodHook(){
                    @Override protected void beforeHookedMethod(MethodHookParam call){
                        if(active()&&gmsRegistryLogs.incrementAndGet()<=16)emit(name.equals("c")?"REGISTRY_START_ENTERED":"REGISTRY_STOP_ENTERED","kind=OBSERVATION");
                    }
                    @Override protected void afterHookedMethod(MethodHookParam call){
                        if(active()&&gmsRegistryLogs.incrementAndGet()<=16)emit(name.equals("c")?"REGISTRY_START_RETURNED":"REGISTRY_STOP_RETURNED",
                                "outcome="+(call.hasThrowable()?"THREW":"RETURNED"));
                    }
                });
            }
            try{
                Class<?> param=target("com.google.android.gms.nearby.sharing.internal.ProviderShutdownParams",info,until);
                final AtomicInteger gmsShutdownEvents=new AtomicInteger();
                for(final String type:new String[]{"ekde","ekdf"}){
                    Method method=target(type,info,until).getDeclaredMethod("g",param);
                    if(method.getReturnType()!=void.class||Modifier.isStatic(method.getModifiers()))throw new Exception("TASK_SIGNATURE");
                    hook(method,new XC_MethodHook(){@Override protected void beforeHookedMethod(MethodHookParam call){
                        if(active()&&gmsShutdownEvents.incrementAndGet()<=16)emitCritical("GMS_PROVIDER_SHUTDOWN_CALL","kind="+("ekde".equals(type)?"REMOTE":"WRAPPER"));
                    }});
                }
                emitCritical("GMS_SHUTDOWN_OBSERVER_READY","kind=READONLY");
            }catch(Throwable ignored){emitCritical("GMS_SHUTDOWN_OBSERVER_UNAVAILABLE","kind=READONLY");}
            try{
                Class<?> service=target("com.google.android.gms.nearby.sharing.NearbySharingChimeraService",info,until);
                Method destroy=service.getDeclaredMethod("onDestroy"),shutdown=service.getDeclaredMethod("aF"),toggle=service.getDeclaredMethod("t",boolean.class);
                if(destroy.getReturnType()!=void.class||shutdown.getReturnType()!=void.class||toggle.getReturnType()!=int.class||Modifier.isStatic(destroy.getModifiers())||Modifier.isStatic(shutdown.getModifiers())||Modifier.isStatic(toggle.getModifiers()))throw new Exception("TASK_SIGNATURE");
                final AtomicInteger calls=new AtomicInteger();
                for(final Method m:new Method[]{destroy,shutdown,toggle})hook(m,new XC_MethodHook(){@Override protected void beforeHookedMethod(MethodHookParam call){
                    if(!active()||calls.incrementAndGet()>32)return;
                    String kind=m==destroy?"DESTROY":m==shutdown?"SHUTDOWN":"ENABLE_TOGGLE";
                    String state=m==toggle&&call.args!=null&&call.args.length==1&&call.args[0] instanceof Boolean?(Boolean.TRUE.equals(call.args[0])?"TRUE":"FALSE"):"NONE";
                    emitCritical("GMS_SHARING_SERVICE_CALL","kind="+kind+" state="+state);
                }});
                emitCritical("GMS_SERVICE_OBSERVER_READY","kind=READONLY");
            }catch(Throwable ignored){emitCritical("GMS_SERVICE_OBSERVER_UNAVAILABLE","kind=READONLY");}
        }
        void installMosey(ApplicationInfo info,long until)throws Exception{
            // APK hash admission has completed. Make the narrow real-Binder adapter
            // ready before loading optional observers, which can race app startup.
            installNativeLookup(until);
            installUpdatedNativeObservation(info,until);
            installDiscoverObservation(info,until);
            installTlsSocketObservation(until);
            installSendObservation(info,until);
            installRawRouteObservation(info,until);
            installReceiveObservation(info,until);
            installReceiveStatusObservation(info,until);
            installReceiveCollectorObservation(info,until);
            installReceiveCallbackRecovery(info,until);
            installFixtureReadObservation(info,until);
        }
        // Preserve the callback for the individual collector while it is live.
        // Recover only a real COMPLETE event when both original callback paths
        // are empty. Never manufacture a terminal state from a file or timer.
        void installReceiveCallbackRecovery(ApplicationInfo info,long until){
            try{
                Class<?> collector=target("ecj",info,until), provider=target("cen",info,until);
                Class<?> update=target("buw",info,until), continuation=target("dqd",info,until);
                Class<?> metadata=target("com.google.android.gms.nearby.sharing.TransferMetadata",info,until);
                Class<?> shareTarget=target("com.google.android.gms.nearby.sharing.ShareTarget",info,until);
                Class<?> callback=target("dsc",info,until), unit=target("doq",info,until);
                Field kind=collector.getDeclaredField("c"), owner=collector.getDeclaredField("a");
                Field saved=collector.getDeclaredField("b"), current=provider.getDeclaredField("n");
                Field body=update.getDeclaredField("b"), recipient=update.getDeclaredField("a");
                Field status=metadata.getDeclaredField("a"), terminal=metadata.getDeclaredField("e");
                Field unitValue=unit.getDeclaredField("a");
                Method consume=collector.getDeclaredMethod("cp",Object.class,continuation);
                Method deliver=callback.getDeclaredMethod("a",Object.class,Object.class);
                if(kind.getType()!=int.class||owner.getType()!=Object.class||saved.getType()!=Object.class
                        ||current.getType()!=callback||body.getType()!=metadata||recipient.getType()!=shareTarget
                        ||status.getType()!=int.class||terminal.getType()!=boolean.class||unitValue.getType()!=unit
                        ||!Modifier.isStatic(unitValue.getModifiers())||consume.getReturnType()!=Object.class
                        ||deliver.getReturnType()!=Object.class||Modifier.isStatic(consume.getModifiers())
                        ||Modifier.isAbstract(consume.getModifiers())||Modifier.isNative(consume.getModifiers()))
                    throw new Exception("STATUS_SIGNATURE");
                for(Field f:new Field[]{kind,owner,saved,current,body,recipient,status,terminal,unitValue})f.setAccessible(true);
                deliver.setAccessible(true);
                final Object unitResult=unitValue.get(null);
                if(unitResult==null)throw new Exception("STATUS_SIGNATURE");
                hook(consume,new XC_MethodHook(){
                    @Override protected void beforeHookedMethod(MethodHookParam call){
                        if(!active()||call.args==null||call.args.length!=2||!update.isInstance(call.args[0]))return;
                        try{
                            if(kind.getInt(call.thisObject)==0)return;
                            Object own=owner.get(call.thisObject);
                            if(!provider.isInstance(own))return;
                            Object shared=current.get(own), originalSaved=saved.get(call.thisObject);
                            if(callback.isInstance(shared))receiveCallbacks.remember(call.thisObject,shared);
                            Object meta=body.get(call.args[0]);
                            if(!metadata.isInstance(meta)||!terminal.getBoolean(meta))return;
                            call.setObjectExtra("GT8_RECEIVE_TERMINAL",Boolean.TRUE);
                            Object retained=receiveCallbacks.get(call.thisObject), targetValue=recipient.get(call.args[0]);
                            if(!ReceiveCallbackCache.recoverable(status.getInt(meta),true,shared,originalSaved,retained))return;
                            if(!callback.isInstance(retained)||!shareTarget.isInstance(targetValue))return;
                            deliver.invoke(retained,targetValue,meta);
                            call.setResult(unitResult);
                            emitCritical("RECEIVE_CALLBACK_RECOVERY","result=DELIVERED");
                        }catch(Throwable ignored){emitCritical("RECEIVE_CALLBACK_RECOVERY","result=UNCONFIRMED");}
                    }
                    @Override protected void afterHookedMethod(MethodHookParam call){
                        if(Boolean.TRUE.equals(call.getObjectExtra("GT8_RECEIVE_TERMINAL")))receiveCallbacks.remove(call.thisObject);
                    }
                });
                emitCritical("RECEIVE_CALLBACK_RECOVERY_READY","scope=COMPLETE_WITH_MISSING_CALLBACK");
            }catch(Throwable ignored){emitCritical("RECEIVE_CALLBACK_RECOVERY_UNAVAILABLE","kind=FAIL_CLOSED");}
        }
        void installReceiveCollectorObservation(ApplicationInfo info,long until){
            try{
                Class<?> collector=target("ecj",info,until), provider=target("cen",info,until);
                Class<?> update=target("buw",info,until), continuation=target("dqd",info,until);
                Class<?> metadata=target("com.google.android.gms.nearby.sharing.TransferMetadata",info,until);
                Class<?> callback=target("dsc",info,until);
                Field kind=collector.getDeclaredField("c"), owner=collector.getDeclaredField("a");
                Field saved=collector.getDeclaredField("b"), current=provider.getDeclaredField("n");
                Field body=update.getDeclaredField("b"), status=metadata.getDeclaredField("a"), end=metadata.getDeclaredField("e");
                Method consume=collector.getDeclaredMethod("cp",Object.class,continuation);
                if(kind.getType()!=int.class||owner.getType()!=Object.class||saved.getType()!=Object.class
                        ||current.getType()!=callback||body.getType()!=metadata||status.getType()!=int.class
                        ||end.getType()!=boolean.class||consume.getReturnType()!=Object.class
                        ||Modifier.isStatic(consume.getModifiers())||Modifier.isNative(consume.getModifiers())
                        ||Modifier.isAbstract(consume.getModifiers()))throw new Exception("STATUS_SIGNATURE");
                for(Field f:new Field[]{kind,owner,saved,current,body,status,end})f.setAccessible(true);
                final AtomicInteger events=new AtomicInteger();
                hook(consume,new XC_MethodHook(){
                    @Override protected void beforeHookedMethod(MethodHookParam call){
                        if(!active()||call.args==null||call.args.length!=2||!update.isInstance(call.args[0]))return;
                        try{
                            if(kind.getInt(call.thisObject)==0)return;
                            Object meta=body.get(call.args[0]);int code=status.getInt(meta);
                            if(code==1005||events.incrementAndGet()>40)return;
                            Object who=owner.get(call.thisObject), old=saved.get(call.thisObject);
                            boolean captured=callback.isInstance(old), shared=provider.isInstance(who)&&callback.isInstance(current.get(who));
                            String safe=code>=1000&&code<=1100?Integer.toString(code):"OTHER";
                            emit("RECEIVE_COLLECTOR","code="+safe+" terminal="+(end.getBoolean(meta)?"YES":"NO")+" saved="+(captured?"YES":"NO")+" shared="+(shared?"YES":"NO"));
                        }catch(Throwable ignored){emit("RECEIVE_COLLECTOR","code=UNREADABLE");}
                    }
                });
                emit("RECEIVE_COLLECTOR_OBSERVER_READY","kind=READONLY");
            }catch(Throwable ignored){emit("RECEIVE_COLLECTOR_OBSERVER_UNAVAILABLE","kind=READONLY");}
        }
        // Observe status codes and dispatch outcomes only. Never modify a
        // status or log a transfer identifier, file, peer, or callback value.
        void installReceiveStatusObservation(ApplicationInfo info,long until){
            try{
                Class<?> provider=target("cen",info,until);
                Class<?> transfer=target("ccu",info,until);
                Class<?> update=target("buw",info,until);
                Class<?> continuation=target("dqd",info,until);
                Class<?> metadata=target("com.google.android.gms.nearby.sharing.TransferMetadata",info,until);
                Field updateMetadata=update.getDeclaredField("b");
                Field status=metadata.getDeclaredField("a"), terminal=metadata.getDeclaredField("e");
                Method dispatch=provider.getDeclaredMethod("l",transfer,update,continuation);
                if(updateMetadata.getType()!=metadata||status.getType()!=int.class||terminal.getType()!=boolean.class
                        ||dispatch.getReturnType()!=Object.class||Modifier.isStatic(dispatch.getModifiers())
                        ||Modifier.isAbstract(dispatch.getModifiers())||Modifier.isNative(dispatch.getModifiers()))
                    throw new Exception("STATUS_SIGNATURE");
                updateMetadata.setAccessible(true);status.setAccessible(true);terminal.setAccessible(true);
                final AtomicInteger observed=new AtomicInteger();
                hook(dispatch,new XC_MethodHook(){
                    @Override protected void beforeHookedMethod(MethodHookParam call){
                        if(!active()||call.args==null||call.args.length!=3||observed.incrementAndGet()>64)return;
                        try{
                            Object value=updateMetadata.get(call.args[1]);
                            int code=status.getInt(value);
                            String safe=code>=1000&&code<=1100?Integer.toString(code):"OTHER";
                            emit("RECEIVE_STATUS_DISPATCH","code="+safe+" terminal="+(terminal.getBoolean(value)?"YES":"NO"));
                        }catch(Throwable ignored){emit("RECEIVE_STATUS_DISPATCH","code=UNREADABLE terminal=UNKNOWN");}
                    }
                });
                emit("RECEIVE_STATUS_OBSERVER_READY","kind=READONLY");
            }catch(Throwable ignored){emit("RECEIVE_STATUS_OBSERVER_UNAVAILABLE","kind=READONLY");}
        }
        void installNativeLookup(long until)throws Exception{
            Class<?> manager=Class.forName("android.os.ServiceManager",false,null);
            final Method check=manager.getDeclaredMethod("checkService",String.class);
            check.setAccessible(true);
            final Method declared=manager.getDeclaredMethod("isDeclared",String.class);
            declared.setAccessible(true);
            Method wait=manager.getDeclaredMethod("waitForDeclaredService",String.class);
            hook(wait,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call){
                    if(!nativeActive()||call.args==null||call.args.length!=1
                            ||!HookLogic.INSTANCE.equals(call.args[0]))return;
                    emit("NATIVE_LOOKUP_ENTERED","instance=ANDROID origin="+lookupOrigin());
                    Object declaration=null;
                    if(BuildVariant.BINDER)try{declaration=declared.invoke(null,HookLogic.INSTANCE);}catch(Throwable ignored){}
                    HookLogic.Decision result=HookLogic.lookupDeclared((String)call.args[0],BuildVariant.BINDER,
                            nativeArmed,SystemClock.elapsedRealtime(),deadline,declaration,()->{
                                Object b=check.invoke(null,HookLogic.INSTANCE);
                                if(!(b instanceof IBinder))return null;
                                final IBinder binder=(IBinder)b;
                                return new HookLogic.BinderView(){
                                    public boolean alive(){return binder.isBinderAlive();}
                                    public String descriptor()throws Exception{return binder.getInterfaceDescriptor();}
                                    public Object value(){return binder;}
                                };
                            });
                    synchronized(lock){
                        if(result.intercept&&result.binder!=null&&nativeActive()){
                            call.setResult(result.binder);emit("NATIVE_LOOKUP_ADAPTER","result="+result.event+" origin="+lookupOrigin());
                        }else if(BuildVariant.BINDER&&nativeActive()){
                            emit("NATIVE_LOOKUP_ADAPTER_SKIPPED","result="+result.event+" origin="+lookupOrigin());
                        }
                    }
                }
                @Override protected void afterHookedMethod(MethodHookParam call){
                    if(nativeActive()&&call.args!=null&&call.args.length==1&&HookLogic.INSTANCE.equals(call.args[0]))
                        emit("NATIVE_LOOKUP_RETURNED","result="+(call.hasThrowable()?"THREW":call.getResult()==null?"NULL":"NONNULL")+" origin="+lookupOrigin());
                }
            });
            synchronized(lock){
                if(stopped||SystemClock.elapsedRealtime()>=Math.min(until,deadline))throw new Exception("EXPIRED");
                nativeArmed=true;
            }
            emit("NATIVE_ADAPTER_READY","kind=REAL_BINDER_ONLY");
        }
        void installUpdatedNativeObservation(ApplicationInfo info,long until)throws Exception {
            Class<?> factory=target("bwz",info,until),backend=target("bxc",info,until);
            Method get=factory.getDeclaredMethod("a");
            if(get.getReturnType()!=backend||!Modifier.isStatic(get.getModifiers())||Modifier.isNative(get.getModifiers()))
                throw new Exception("CALLBACK_SIGNATURE");
            hook(get,new XC_MethodHook(){
                @Override protected void afterHookedMethod(MethodHookParam call){
                    if(!sdkObservationOpen()||call.hasThrowable())return;
                    try{
                        if(call.getResult()==null){emit("APP_BACKEND","result=NULL");return;}
                        Class<?> type=call.getResult().getClass();
                        String name=type.getName();
                        final String kind="bwy".equals(name)?"ANDROID":"bxa".equals(name)?"PIXEL":"bxb".equals(name)?"PLATFORM":"OTHER";
                        if("OTHER".equals(kind)){emit("APP_BACKEND","result=OTHER");return;}
                        SourceGuard.owner(type,info,Math.min(deadline,SystemClock.elapsedRealtime()+1000));
                        emit("APP_BACKEND","result="+kind);
                        synchronized(lock){
                            if(!nativeVersionHooks.add(type))return;
                            Method version=type.getDeclaredMethod("b");
                            if(version.getReturnType()!=String.class||Modifier.isStatic(version.getModifiers())||Modifier.isNative(version.getModifiers()))throw new Exception("CALLBACK_SIGNATURE");
                            hook(version,new XC_MethodHook(){
                                @Override protected void afterHookedMethod(MethodHookParam value){
                                    if(!sdkObservationOpen())return;
                                    Object v=value.getResult();String fixed=v instanceof String&&((String)v).matches("[APS][1-9][0-9]{0,2}")?(String)v:"OTHER";
                                    emit("APP_NATIVE_VERSION","backend="+kind+" value="+fixed+" outcome="+(value.hasThrowable()?"THREW":"RETURNED"));
                                }
                            });
                        }
                    }catch(Throwable ignored){emit("APP_BACKEND","result=UNAVAILABLE");}
                }
            });
        }
        void installSendObservation(ApplicationInfo info,long until)throws Exception{
            final Class<?> suspended=target("dqj",info,until);
            for(String name:new String[]{"cbp","cbs","cbx","cca"}){
                Class<?> task=target(name,info,until);Method run=task.getDeclaredMethod("b",Object.class);
                if(run.getReturnType()!=Object.class||Modifier.isStatic(run.getModifiers())||Modifier.isNative(run.getModifiers())||Modifier.isAbstract(run.getModifiers()))throw new Exception("TASK_SIGNATURE");
                hook(run,new XC_MethodHook(){
                    @Override protected void beforeHookedMethod(MethodHookParam call){
                        if(!active())return;
                        int id;
                        id=sendTasks.acquire(call.thisObject);if(id==0)return;
                        call.setObjectExtra("GT8_SEND_PREVIOUS",sendSlot.get());call.setObjectExtra("GT8_SEND_SLOT",id);sendSlot.set(id);emit("SEND_TASK_ENTER","slot="+id);
                    }
                    @Override protected void afterHookedMethod(MethodHookParam call){
                        Object id=call.getObjectExtra("GT8_SEND_SLOT");if(!(id instanceof Integer))return;
                        try{if(active())emit("SEND_TASK_RETURN","slot="+id+" result="+(call.hasThrowable()?"THREW":call.getResult()!=null&&call.getResult().getClass()==suspended?"SUSPENDED":"RETURNED"));}
                        finally{if(call.hasThrowable()||call.getResult()==null||call.getResult().getClass()!=suspended)sendTasks.release(call.thisObject);Object previous=call.getObjectExtra("GT8_SEND_PREVIOUS");if(previous instanceof Integer)sendSlot.set((Integer)previous);else sendSlot.remove();}
                    }
                });
            }
            Class<?> callType=target("emn",info,until),callback=target("epi",info,until),response=target("elf",info,until);
            Method enqueue=callType.getDeclaredMethod("k",callback),network=callType.getDeclaredMethod("f");Field status=response.getDeclaredField("d");
            if(enqueue.getReturnType()!=void.class||Modifier.isStatic(enqueue.getModifiers())||network.getReturnType()!=response||Modifier.isStatic(network.getModifiers())||status.getType()!=int.class||!Modifier.isFinal(status.getModifiers()))throw new Exception("TASK_SIGNATURE");
            status.setAccessible(true);
            hook(enqueue,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call){
                    Integer slot=sendSlot.get();if(!active()||slot==null)return;
                    synchronized(sendCalls){if(sendCalls.size()>=8)return;sendCalls.put(call.thisObject,slot);}
                    emit("SEND_HTTP_SUBMITTED","slot="+slot);
                }
                @Override protected void afterHookedMethod(MethodHookParam call){if(call.hasThrowable())synchronized(sendCalls){sendCalls.remove(call.thisObject);}}
            });
            hook(network,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call){
                    Integer slot;synchronized(sendCalls){slot=sendCalls.get(call.thisObject);}if(!active()||slot==null)return;
                    call.setObjectExtra("GT8_ASYNC_SEND_PREVIOUS",sendSlot.get());call.setObjectExtra("GT8_ASYNC_SEND_SLOT",slot);sendSlot.set(slot);emit("SEND_HTTP_ENTER","slot="+slot);
                    final int id=slot;final Thread current=Thread.currentThread();sendThreads.put(id,current);
                    for(int delay:new int[]{250,1500,4000,8000})workers.schedule(()->{
                        if(!active()||sendThreads.get(id)!=current)return;
                        try{emit("SEND_HTTP_WAIT","slot="+id+" phase="+DiscoverLogic.phase(current.getStackTrace()));}catch(Throwable ignored){}
                    },delay,TimeUnit.MILLISECONDS);
                }
                @Override protected void afterHookedMethod(MethodHookParam call){
                    Object slot=call.getObjectExtra("GT8_ASYNC_SEND_SLOT");if(!(slot instanceof Integer))return;
                    try{if(active()){
                        if(call.hasThrowable())emit("SEND_HTTP_RETURN","slot="+slot+" result=THREW"+failureFields(call.getThrowable()));
                        else if(response.isInstance(call.getResult()))emit("SEND_HTTP_RETURN","slot="+slot+" result=RESPONSE code="+DiscoverLogic.status(status.getInt(call.getResult())));
                        else emit("SEND_HTTP_RETURN","slot="+slot+" result=OTHER");
                    }}catch(Throwable ignored){}
                    finally{sendThreads.remove((Integer)slot);synchronized(sendCalls){sendCalls.remove(call.thisObject);}Object old=call.getObjectExtra("GT8_ASYNC_SEND_PREVIOUS");if(old instanceof Integer)sendSlot.set((Integer)old);else sendSlot.remove();}
                }
            });
            emit("SEND_OBSERVER_READY","kind=READONLY");
        }
        void installReceiveObservation(ApplicationInfo info,long until)throws Exception{
            Class<?> manager=target("cen",info,until),transport=target("cea",info,until),connection=target("dgc",info,until),server=target("dfx",info,until);
            Class<?> nsd=target("ced",info,until),plist=target("adl",info,until),reply=target("bvv",info,until);
            final Field bound=transport.getDeclaredField("b");
            Method accept=transport.getDeclaredMethod("b",connection),error=transport.getDeclaredMethod("a",Exception.class);
            if(bound.getType()!=server||Modifier.isStatic(bound.getModifiers())||accept.getReturnType()!=void.class||error.getReturnType()!=void.class||Modifier.isStatic(accept.getModifiers())||Modifier.isStatic(error.getModifiers()))throw new Exception("TASK_SIGNATURE");
            bound.setAccessible(true);final AtomicInteger accepted=new AtomicInteger();
            hook(accept,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call){
                    if(!active()||accepted.incrementAndGet()>12)return;
                    try{String stage=bound.get(call.thisObject)==null?"LISTEN":"ACCEPT";call.setObjectExtra("GT8_RECEIVE_STAGE",stage);emit("RECEIVE_TRANSPORT_ENTER","stage="+stage);}catch(Throwable ignored){}
                }
                @Override protected void afterHookedMethod(MethodHookParam call){
                    Object stage=call.getObjectExtra("GT8_RECEIVE_STAGE");if(!(stage instanceof String)||!active())return;
                    emit("RECEIVE_TRANSPORT_RETURN","stage="+stage+" result="+(call.hasThrowable()?"THREW":"RETURNED")+(call.hasThrowable()?failureFields(call.getThrowable()):""));
                }
            });
            hook(error,new XC_MethodHook(){@Override protected void beforeHookedMethod(MethodHookParam call){
                if(active()&&call.args!=null&&call.args.length==1&&call.args[0] instanceof Throwable)emit("RECEIVE_TRANSPORT_ERROR","stage=IO"+failureFields((Throwable)call.args[0]));
            }});
            Method registered=nsd.getDeclaredMethod("onServiceRegistered",android.net.nsd.NsdServiceInfo.class),failed=nsd.getDeclaredMethod("onRegistrationFailed",android.net.nsd.NsdServiceInfo.class,int.class);
            if(registered.getReturnType()!=void.class||failed.getReturnType()!=void.class||!android.net.nsd.NsdManager.RegistrationListener.class.isAssignableFrom(nsd))throw new Exception("TASK_SIGNATURE");
            hook(registered,new XC_MethodHook(){@Override protected void afterHookedMethod(MethodHookParam call){if(active())emit("RECEIVE_NSD_REGISTERED","result="+(call.hasThrowable()?"THREW":"RETURNED"));}});
            hook(failed,new XC_MethodHook(){@Override protected void beforeHookedMethod(MethodHookParam call){if(active()){Object code=call.args!=null&&call.args.length==2?call.args[1]:null;emit("RECEIVE_NSD_FAILED","code="+(code instanceof Integer&&((Integer)code)>=0&&((Integer)code)<=99?code:"OTHER"));}}});
            final Class<?> plistValue=target("ado",info,until),plistArray=target("adg",info,until),plistNumber=target("adn",info,until);
            final Method plistGet=plist.getDeclaredMethod("b",Object.class),plistLong=plistNumber.getDeclaredMethod("a");
            final Field plistItems=plistArray.getDeclaredField("a");
            if(plistGet.getReturnType()!=plistValue||plistLong.getReturnType()!=long.class||plistItems.getType()!=java.lang.reflect.Array.newInstance(plistValue,0).getClass()||Modifier.isStatic(plistGet.getModifiers())||Modifier.isStatic(plistLong.getModifiers())||Modifier.isStatic(plistItems.getModifiers()))throw new Exception("TASK_SIGNATURE");
            plistGet.setAccessible(true);plistLong.setAccessible(true);plistItems.setAccessible(true);
            Method unregistered=nsd.getDeclaredMethod("onServiceUnregistered",android.net.nsd.NsdServiceInfo.class);
            if(unregistered.getReturnType()!=void.class)throw new Exception("TASK_SIGNATURE");
            hook(unregistered,new XC_MethodHook(){@Override protected void afterHookedMethod(MethodHookParam call){if(active())emit("RECEIVE_NSD_UNREGISTERED","result="+(call.hasThrowable()?"THREW":"RETURNED"));}});
            Class<?> sdk=target("cad",info,until),options=target("apj",info,until),callback=target("aqa",info,until);
            final Field visibility=options.getDeclaredField("a"),deviceName=options.getDeclaredField("b"),optionC=options.getDeclaredField("c");
            if(visibility.getType()!=int.class||deviceName.getType()!=String.class||optionC.getType()!=boolean.class||Modifier.isStatic(visibility.getModifiers())||Modifier.isStatic(deviceName.getModifiers())||Modifier.isStatic(optionC.getModifiers()))throw new Exception("TASK_SIGNATURE");
            visibility.setAccessible(true);deviceName.setAccessible(true);optionC.setAccessible(true);
            final AtomicInteger optionEvents=new AtomicInteger();
            for(final String kind:new String[]{"START","UPDATE"}){
                Method optionMethod=kind.equals("START")?sdk.getDeclaredMethod("f",options,callback):sdk.getDeclaredMethod("j",options);
                if(optionMethod.getReturnType()!=int.class||Modifier.isStatic(optionMethod.getModifiers()))throw new Exception("TASK_SIGNATURE");
                hook(optionMethod,new XC_MethodHook(){
                    @Override protected void beforeHookedMethod(MethodHookParam call){
                        if(!active()||optionEvents.incrementAndGet()>64||call.args==null||call.args.length<1||!options.isInstance(call.args[0]))return;
                        try{int v=visibility.getInt(call.args[0]);Object n=deviceName.get(call.args[0]);boolean c=optionC.getBoolean(call.args[0]);
                            call.setObjectExtra("GT8_OPTIONS_SEEN",Boolean.TRUE);
                            emit("ADVERTISING_OPTIONS","kind="+kind+" visibility="+(v>=0&&v<=8?Integer.toString(v):"OTHER")+" option_c="+(c?"TRUE":"FALSE")+" name="+(n instanceof String&&!((String)n).isEmpty()?"PRESENT":"EMPTY"));
                        }catch(Throwable ignored){}
                    }
                    @Override protected void afterHookedMethod(MethodHookParam call){
                        if(active()&&Boolean.TRUE.equals(call.getObjectExtra("GT8_OPTIONS_SEEN"))){Object r=call.getResult();emit("ADVERTISING_OPTIONS_RETURN","kind="+kind+" result="+(call.hasThrowable()?"THREW":r instanceof Integer&&((Integer)r)>=0&&((Integer)r)<=999?r.toString():"OTHER"));}
                    }
                });
            }
            final AtomicInteger requests=new AtomicInteger();
            for(final String path:new String[]{"DISCOVER","ASK","UPLOAD"}){
                Class<?> type=target(path.equals("DISCOVER")?"cdv":path.equals("ASK")?"cdw":"bvr",info,until);
                Method method;
                if(path.equals("UPLOAD")){
                    Field owner=type.getDeclaredField("b");if(owner.getType()!=manager||Modifier.isStatic(owner.getModifiers()))throw new Exception("TASK_SIGNATURE");
                    method=type.getDeclaredMethod("a",target("diw",info,until),target("diz",info,until));
                }else method=type.getDeclaredMethod("c",java.net.InetSocketAddress.class,plist,reply);
                if(method.getReturnType()!=void.class||Modifier.isStatic(method.getModifiers())||Modifier.isAbstract(method.getModifiers())||Modifier.isNative(method.getModifiers()))throw new Exception("TASK_SIGNATURE");
                hook(method,new XC_MethodHook(){
                    @Override protected void beforeHookedMethod(MethodHookParam call){if(!active()||requests.incrementAndGet()>12)return;call.setObjectExtra("GT8_RX_REQUEST",Boolean.TRUE);emit("RECEIVE_REQUEST_ENTER","path="+path);if(path.equals("ASK")){
                        String outcome="SHAPE_UNCONFIRMED";
                        try{
                            if(call.args!=null&&call.args.length==3&&plist.isInstance(call.args[1])){
                                Object files=plistGet.invoke(call.args[1],"Files");
                                if(plistArray.isInstance(files)){
                                    Object items=plistItems.get(files);int count=java.lang.reflect.Array.getLength(items);
                                    if(count!=1)outcome="NOT_SINGLE_FILE";
                                    else{
                                        Object item=java.lang.reflect.Array.get(items,0);
                                        if(plist.isInstance(item)){
                                            Object name=plistGet.invoke(item,"FileName"),size=plistGet.invoke(item,"FileSize"),kind=plistGet.invoke(item,"FileType"),sender=plistGet.invoke(call.args[1],"SenderComputerName");
                                            outcome=ReceiveFixtureLogic.classify(count,plistValue.isInstance(name)?name.toString():null,plistNumber.isInstance(size)?(Long)plistLong.invoke(size):null,plistValue.isInstance(kind)?kind.toString():null,plistValue.isInstance(sender)?sender.toString():null);
                                        }
                                    }
                                }
                            }
                        }catch(Throwable ignored){}
                        emit("RECEIVE_OWN_FIXTURE_ASK","result="+outcome);
                    }}
                    @Override protected void afterHookedMethod(MethodHookParam call){if(active()&&Boolean.TRUE.equals(call.getObjectExtra("GT8_RX_REQUEST")))emit("RECEIVE_REQUEST_RETURN","path="+path+" result="+(call.hasThrowable()?"THREW":"RETURNED")+(call.hasThrowable()?failureFields(call.getThrowable()):""));}
                });
            }
            try{
                Class<?> provider=target("btb",info,until),shutdownRequest=target("arj",info,until),managerApi=target("cce",info,until),continuation=target("dqd",info,until);
                Method binderShutdown=provider.getDeclaredMethod("i",shutdownRequest),asyncShutdown=managerApi.getDeclaredMethod("l",continuation);
                if(binderShutdown.getReturnType()!=void.class||asyncShutdown.getReturnType()!=Object.class||Modifier.isStatic(binderShutdown.getModifiers())||Modifier.isStatic(asyncShutdown.getModifiers()))throw new Exception("TASK_SIGNATURE");
                final AtomicInteger shutdownEvents=new AtomicInteger();
                hook(binderShutdown,new XC_MethodHook(){@Override protected void beforeHookedMethod(MethodHookParam call){
                    if(!active()||shutdownEvents.incrementAndGet()>16)return;
                    int uid=android.os.Binder.getCallingUid();String caller=uid==Process.myUid()?"SELF":uid==Process.SYSTEM_UID?"SYSTEM":gmsUid>=0&&uid==gmsUid?"GMS":"OTHER_OR_UNKNOWN";
                    emitCritical("PROVIDER_SHUTDOWN_CALL","caller="+caller);
                }});
                hook(asyncShutdown,new XC_MethodHook(){@Override protected void beforeHookedMethod(MethodHookParam call){
                    if(active()&&shutdownEvents.incrementAndGet()<=16)emitCritical("PROVIDER_ASYNC_SHUTDOWN_CALL","kind=OBSERVED");
                }});
                emitCritical("PROVIDER_SHUTDOWN_OBSERVER_READY","kind=READONLY");
            }catch(Throwable ignored){emitCritical("PROVIDER_SHUTDOWN_OBSERVER_UNAVAILABLE","kind=READONLY");}
            emit("RECEIVE_OBSERVER_READY","kind=READONLY");
        }
        void installFixtureReadObservation(ApplicationInfo info,long until)throws Exception{
            Class<?> files=target("cfh",info,until);
            Method open=files.getDeclaredMethod("b",Context.class,android.net.Uri.class);
            if(open.getReturnType()!=java.io.InputStream.class||Modifier.isStatic(open.getModifiers())||Modifier.isNative(open.getModifiers())||Modifier.isAbstract(open.getModifiers()))throw new Exception("TASK_SIGNATURE");
            final AtomicInteger count=new AtomicInteger();
            hook(open,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call){
                    if(!active()||call.args==null||call.args.length!=2||!(call.args[0] instanceof Context)||!FixtureProvider.URI.equals(call.args[1])||count.incrementAndGet()>4)return;
                    call.setObjectExtra("GT8_OWN_FIXTURE_READ",Boolean.TRUE);
                    Context ctx=(Context)call.args[0];
                    int caller=android.os.Binder.getCallingUid();
                    String who=caller==Process.myUid()?"SELF":caller==0?"ROOT":caller<10000?"SYSTEM":caller>=100000?"OTHER_USER":"USER0_APP";
                    String pkg="UNAVAILABLE",user="UNAVAILABLE",visible="UNAVAILABLE",grant="UNAVAILABLE";
                    try{String p=ctx.getPackageName();pkg="com.google.android.mosey".equals(p)?"MOSEY":"com.google.android.gms".equals(p)?"GMS":"android".equals(p)?"ANDROID":"OTHER";}catch(Throwable ignored){}
                    try{Method get=Context.class.getDeclaredMethod("getUserId");get.setAccessible(true);Object value=get.invoke(ctx);if(value instanceof Integer)user=((Integer)value)==0?"USER0":"OTHER_USER";}catch(Throwable ignored){}
                    try{visible=ctx.getPackageManager().resolveContentProvider("local.gt8pro.moseybridge.fixture",0)==null?"HIDDEN":"VISIBLE";}catch(Throwable ignored){}
                    try{grant=ctx.checkUriPermission(FixtureProvider.URI,Process.myPid(),Process.myUid(),Intent.FLAG_GRANT_READ_URI_PERMISSION)==android.content.pm.PackageManager.PERMISSION_GRANTED?"GRANTED":"DENIED";}catch(Throwable ignored){}
                    emit("FIXTURE_READ_ENTER","context="+pkg+" user="+user+" caller="+who+" provider="+visible+" grant="+grant);
                }
                @Override protected void afterHookedMethod(MethodHookParam call){
                    if(active()&&Boolean.TRUE.equals(call.getObjectExtra("GT8_OWN_FIXTURE_READ"))){Throwable t=call.getThrowable();emit("FIXTURE_READ_RETURN","result="+(t instanceof java.io.FileNotFoundException?"NOT_FOUND":t instanceof SecurityException?"DENIED":t!=null?"OTHER_ERROR":call.getResult() instanceof java.io.InputStream?"OPENED":"EMPTY"));}
                }
            });
            emit("FIXTURE_READ_OBSERVER_READY","kind=OWN_SYNTHETIC_ONLY");
        }
        void installRawRouteObservation(ApplicationInfo info,long until)throws Exception{
            Class<?> raw=target("cfo",info,until),route=target("emv",info,until);
            Class<?> address=target("ejz",info,until),queue=target("djq",info,until),callType=target("emn",info,until),urlType=target("eku",info,until),requestType=target("elb",info,until);
            Method connect=raw.getDeclaredMethod("connect",java.net.SocketAddress.class,int.class);
            Field delegate=raw.getDeclaredField("b"),proxies=route.getDeclaredField("d"),url=address.getDeclaredField("h"),request=callType.getDeclaredField("b"),requestUrl=requestType.getDeclaredField("a");
            Method toUri=urlType.getDeclaredMethod("f");
            Constructor<?> create=route.getDeclaredConstructor(address,queue,callType,boolean.class);
            if(!java.net.Socket.class.isAssignableFrom(raw)||connect.getReturnType()!=void.class||Modifier.isStatic(connect.getModifiers())
                    ||delegate.getType()!=java.net.Socket.class||Modifier.isStatic(delegate.getModifiers())||proxies.getType()!=java.util.List.class||Modifier.isStatic(proxies.getModifiers()))throw new Exception("DISCOVER_SIGNATURE");
            if(url.getType()!=urlType||!Modifier.isFinal(url.getModifiers())||Modifier.isStatic(url.getModifiers())||toUri.getReturnType()!=java.net.URI.class||Modifier.isStatic(toUri.getModifiers()))throw new Exception("DISCOVER_SIGNATURE");
            if(request.getType()!=requestType||requestUrl.getType()!=urlType||!Modifier.isFinal(request.getModifiers())||!Modifier.isFinal(requestUrl.getModifiers())||Modifier.isStatic(request.getModifiers())||Modifier.isStatic(requestUrl.getModifiers()))throw new Exception("DISCOVER_SIGNATURE");
            delegate.setAccessible(true);proxies.setAccessible(true);url.setAccessible(true);request.setAccessible(true);requestUrl.setAccessible(true);
            hook(connect,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call){
                    Integer slot=discoverSlot.get();boolean sending=false;if(slot==null){slot=sendSlot.get();sending=true;}if(!active()||slot==null)return;
                    call.setObjectExtra("GT8_RAW_SENDING",sending);call.setObjectExtra("GT8_RAW_SLOT",slot);
                    try{
                        Object a=call.args!=null&&call.args.length==2?call.args[0]:null;
                        java.net.InetAddress target=a instanceof java.net.InetSocketAddress?((java.net.InetSocketAddress)a).getAddress():null;
                        emit(Boolean.TRUE.equals(call.getObjectExtra("GT8_RAW_SENDING"))?"SEND_RAW_CONNECT_ENTER":"DISCOVER_RAW_CONNECT_ENTER","slot="+slot+" target="+DiscoverLogic.addressKind(target));
                    }catch(Throwable ignored){}
                }
                @Override protected void afterHookedMethod(MethodHookParam call){
                    Object slot=call.getObjectExtra("GT8_RAW_SLOT");if(!active()||!(slot instanceof Integer))return;
                    try{
                        Object value=delegate.get(call.thisObject);
                        String peer=value instanceof java.net.Socket?DiscoverLogic.addressKind(((java.net.Socket)value).getInetAddress()):"NONE";
                        emit(Boolean.TRUE.equals(call.getObjectExtra("GT8_RAW_SENDING"))?"SEND_RAW_CONNECT_RETURN":"DISCOVER_RAW_CONNECT_RETURN","slot="+slot+" result="+(call.hasThrowable()?"THREW":"RETURNED")+" peer="+peer);
                    }catch(Throwable ignored){}
                }
            });
            hook(create,new XC_MethodHook(){
                @Override protected void afterHookedMethod(MethodHookParam call){
                    Integer slot=discoverSlot.get();boolean sending=false;if(slot==null){slot=sendSlot.get();sending=true;}if(!active()||slot==null||call.hasThrowable())return;
                    try{
                        Object value=proxies.get(call.thisObject);
                        if(!(value instanceof java.util.List))return;
                        java.util.List<?> list=(java.util.List<?>)value;
                        if(list.isEmpty()||list.size()>8)return;
                        Object valueUri=call.args!=null&&call.args.length==4?toUri.invoke(url.get(call.args[0])):null;
                        java.net.URI origin=valueUri instanceof java.net.URI?(java.net.URI)valueUri:null;
                        Object originalRequest=call.args!=null&&call.args.length==4?request.get(call.args[2]):null;
                        Object originalUrl=originalRequest==null?null:toUri.invoke(requestUrl.get(originalRequest));
                        java.net.URI uri=originalUrl instanceof java.net.URI?(java.net.URI)originalUrl:null;
                        boolean sameOrigin=DiscoveryRouteLogic.sameOrigin(uri,origin);
                        @SuppressWarnings("unchecked") java.util.List<java.net.Proxy> original=(java.util.List<java.net.Proxy>)list;
                        java.util.List<java.net.Proxy> adjusted=sending?DiscoveryRouteLogic.adjustSend(BuildVariant.ROUTE,active()&&sameOrigin,slot,uri,original):DiscoveryRouteLogic.adjust(BuildVariant.ROUTE,active()&&sameOrigin,slot,uri,original);
                        if(adjusted!=original){
                            synchronized(lock){if(active()){proxies.set(call.thisObject,adjusted);list=adjusted;emit(sending?"SEND_ROUTE_COMPAT":"DISCOVER_ROUTE_COMPAT","slot="+slot+" original=HTTP adjusted=DIRECT target=IPV6_LINK_LOCAL");}}
                        }else{
                            String why=!sameOrigin?"ORIGIN":uri==null?"URI_UNAVAILABLE":!"https".equalsIgnoreCase(uri.getScheme())?"SCHEME":!(sending?("/Ask".equals(uri.getRawPath())||"/Upload".equals(uri.getRawPath())):"/Discover".equals(uri.getRawPath()))?"PATH":uri.getPort()<1||uri.getPort()>65535?"PORT":!(sending?DiscoveryRouteLogic.targetSend(uri):DiscoveryRouteLogic.target(uri))?"TARGET":original.size()!=1||original.get(0)==null||original.get(0).type()!=java.net.Proxy.Type.HTTP?"CHOICE":"INACTIVE";
                            emit(sending?"SEND_ROUTE_NOT_ADJUSTED":"DISCOVER_ROUTE_NOT_ADJUSTED","slot="+slot+" reason="+why);
                        }
                        int count=0;
                        for(Object item:list){
                            if(!(item instanceof java.net.Proxy))continue;
                            java.net.Proxy proxy=(java.net.Proxy)item;
                            String kind=proxy.type()==java.net.Proxy.Type.DIRECT?"DIRECT":proxy.type()==java.net.Proxy.Type.HTTP?"HTTP":proxy.type()==java.net.Proxy.Type.SOCKS?"SOCKS":"OTHER";
                            java.net.SocketAddress location=proxy.address();
                            java.net.InetAddress peer=location instanceof java.net.InetSocketAddress?((java.net.InetSocketAddress)location).getAddress():null;
                            emit(sending?"SEND_PROXY_CHOICE":"DISCOVER_PROXY_CHOICE","slot="+slot+" index="+(++count)+" kind="+kind+" peer="+DiscoverLogic.addressKind(peer));
                        }
                    }catch(Throwable ignored){}
                }
            });
            emit("DISCOVER_ROUTE_COMPAT_READY","scope=LINK_LOCAL_DISCOVER_ONLY");
        }
        void installTlsSocketObservation(long until)throws Exception {
            int installed=0;
            for(final String kind:new String[]{"ENGINE","FD"}){
                SourceGuard.time(until);
                String name="com.android.org.conscrypt."+(kind.equals("ENGINE")?"ConscryptEngineSocket":"ConscryptFileDescriptorSocket");
                try{
                    Class<?> type=Class.forName(name,false,null);
                    Method handshake=type.getDeclaredMethod("startHandshake");
                    if(type.getClassLoader()!=javax.net.ssl.SSLSocket.class.getClassLoader()||!javax.net.ssl.SSLSocket.class.isAssignableFrom(type)
                            ||handshake.getDeclaringClass()!=type||handshake.getReturnType()!=void.class||Modifier.isStatic(handshake.getModifiers())
                            ||Modifier.isAbstract(handshake.getModifiers())||Modifier.isNative(handshake.getModifiers()))continue;
                    hook(handshake,new XC_MethodHook(){
                        @Override protected void beforeHookedMethod(MethodHookParam call){
                            Integer slot=discoverSlot.get();boolean sending=false;if(slot==null){slot=sendSlot.get();sending=true;}if(!active()||slot==null||!(call.thisObject instanceof javax.net.ssl.SSLSocket))return;
                            synchronized(tlsObserved){if(tlsObserved.containsKey(call.thisObject)||tlsObserved.size()>=24)return;tlsObserved.put(call.thisObject,Boolean.TRUE);}
                            call.setObjectExtra("GT8_TLS_SOCKET_SENDING",sending);
                            try{
                                javax.net.ssl.SSLSocket socket=(javax.net.ssl.SSLSocket)call.thisObject;
                                call.setObjectExtra("GT8_TLS_SOCKET_SLOT",slot);
                                emit(Boolean.TRUE.equals(call.getObjectExtra("GT8_TLS_SOCKET_SENDING"))?"SEND_TLS_SOCKET_ENTER":"DISCOVER_TLS_SOCKET_ENTER","slot="+slot+" implementation="+kind+" enabled="+DiscoverLogic.protocols(socket.getEnabledProtocols())+" peer="+DiscoverLogic.addressKind(socket.getInetAddress()));
                            }catch(Throwable ignored){}
                        }
                        @Override protected void afterHookedMethod(MethodHookParam call){
                            Object slot=call.getObjectExtra("GT8_TLS_SOCKET_SLOT");if(!(slot instanceof Integer)||!active())return;
                            try{
                                javax.net.ssl.SSLSocket socket=(javax.net.ssl.SSLSocket)call.thisObject;
                                emit(Boolean.TRUE.equals(call.getObjectExtra("GT8_TLS_SOCKET_SENDING"))?"SEND_TLS_SOCKET_RETURN":"DISCOVER_TLS_SOCKET_RETURN","slot="+slot+" result="+(call.hasThrowable()?"THREW":"RETURNED")+" closed="+(socket.isClosed()?"YES":"NO")+" reason="+DiscoverLogic.tlsReason(call.getThrowable()));
                            }catch(Throwable ignored){}
                        }
                    });
                    installed++;
                }catch(ClassNotFoundException|NoSuchMethodException absent){/* Optional boot implementation absent. */}
            }
            emit("TLS_SOCKET_OBSERVER","result="+(installed==2?"BOTH":installed==1?"ONE":"UNAVAILABLE"));
        }
        void installDiscoverObservation(ApplicationInfo info,long until)throws Exception {
            Class<?> task=target("cbz",info,until), http=target("emn",info,until);
            final Class<?> response=target("elf",info,until), boxed=target("dol",info,until);
            final Class<?> failed=target("dok",info,until), success=target("buo",info,until);
            final Field serviceInfo=task.getDeclaredField("a");
            if(serviceInfo.getType()!=android.net.nsd.NsdServiceInfo.class||!Modifier.isFinal(serviceInfo.getModifiers())||Modifier.isStatic(serviceInfo.getModifiers()))throw new Exception("DISCOVER_SIGNATURE");
            serviceInfo.setAccessible(true);
            final Field status=response.getDeclaredField("d"), value=boxed.getDeclaredField("a"), error=failed.getDeclaredField("a");
            final Method run=task.getDeclaredMethod("b",Object.class), execute=http.getDeclaredMethod("e");
            if(run.getReturnType()!=Object.class||execute.getReturnType()!=response
                    ||Modifier.isStatic(run.getModifiers())||Modifier.isStatic(execute.getModifiers())
                    ||Modifier.isNative(run.getModifiers())||Modifier.isAbstract(run.getModifiers())
                    ||Modifier.isNative(execute.getModifiers())||Modifier.isAbstract(execute.getModifiers())
                    ||status.getType()!=int.class||value.getType()!=Object.class||error.getType()!=Throwable.class
                    ||!Modifier.isFinal(status.getModifiers())||!Modifier.isFinal(value.getModifiers())
                    ||!Modifier.isFinal(error.getModifiers())||Modifier.isStatic(status.getModifiers())
                    ||Modifier.isStatic(value.getModifiers())||Modifier.isStatic(error.getModifiers()))
                throw new Exception("DISCOVER_SIGNATURE");
            hook(run,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call) {
                    if(!sdkObservationOpen())return;
                    try {
                        Object ticket=new Object();int slot=discoverTasks.acquire(ticket);if(slot==0)return;
                        call.setObjectExtra("GT8_DISCOVER_TICKET",ticket);
                        int observed=discoverSequence.incrementAndGet();
                        call.setObjectExtra("GT8_PREVIOUS_DISCOVER",discoverSlot.get());
                        call.setObjectExtra("GT8_DISCOVER_SLOT",Integer.valueOf(slot));
                        discoverSlot.set(slot);
                        Thread current=Thread.currentThread();
                        discoverThreads.put(slot,current);
                        emit("DISCOVER_TASK_ENTER","slot="+slot);
                        try{
                            Object raw=serviceInfo.get(call.thisObject);
                            if(raw instanceof android.net.nsd.NsdServiceInfo){
                                android.net.nsd.NsdServiceInfo service=(android.net.nsd.NsdServiceInfo)raw;
                                java.util.List<java.net.InetAddress> hosts=service.getHostAddresses();
                                java.net.InetAddress first=hosts!=null&&!hosts.isEmpty()?hosts.get(0):null;
                                String type=service.getServiceType();
                                String serviceKind="_airdrop._tcp".equals(type)||"_airdrop._tcp.".equals(type)||"._airdrop._tcp.".equals(type)||"_airdrop._tcp.local.".equals(type)?"AIRDROP":"_mosey._tcp".equals(type)||"_mosey._tcp.".equals(type)?"MOSEY":"OTHER";
                                emit("DISCOVER_TARGET_META","slot="+slot+" service="+serviceKind+" first="+DiscoverLogic.addressKind(first)+" port="+(service.getPort()>0&&service.getPort()<=65535?"VALID":"INVALID"));
                            }
                        }catch(Throwable ignored){emit("DISCOVER_TARGET_META","slot="+slot+" result=UNAVAILABLE");}
                        if(observed<=8)for(int delay:new int[]{250,1500,4000})workers.schedule(()->{
                            if(!sdkObservationOpen()||discoverThreads.get(slot)!=current)return;
                            try{emit("DISCOVER_TASK_WAIT","slot="+slot+" phase="+DiscoverLogic.phase(current.getStackTrace()));}
                            catch(Throwable ignored){/* Keep the original operation untouched. */}
                        },delay,TimeUnit.MILLISECONDS);
                    }catch(Throwable ignored){/* Observation never replaces the original call. */}
                }
                @Override protected void afterHookedMethod(MethodHookParam call) {
                    Object marker=call.getObjectExtra("GT8_DISCOVER_SLOT");
                    if(!(marker instanceof Integer))return;
                    int slot=((Integer)marker).intValue();
                    try {
                        if(!sdkObservationOpen())return;
                        if(call.hasThrowable()){
                            emit("DISCOVER_TASK_RETURN","slot="+slot+" result=THREW"+failureFields(call.getThrowable()));
                        }else if(boxed.isInstance(call.getResult())){
                            Object payload=value.get(call.getResult());
                            if(success.isInstance(payload))emit("DISCOVER_TASK_RETURN","slot="+slot+" result=SUCCESS");
                            else if(failed.isInstance(payload))emit("DISCOVER_TASK_RETURN","slot="+slot+" result=FAILED"+failureFields((Throwable)error.get(payload)));
                            else emit("DISCOVER_TASK_RETURN","slot="+slot+" result=OTHER");
                        }else emit("DISCOVER_TASK_RETURN","slot="+slot+" result=OTHER");
                    }catch(Throwable ignored){emit("DISCOVER_TASK_RETURN","slot="+slot+" result=UNAVAILABLE");}
                    finally{
                        discoverThreads.remove(slot);discoverTasks.release(call.getObjectExtra("GT8_DISCOVER_TICKET"));
                        Object previous=call.getObjectExtra("GT8_PREVIOUS_DISCOVER");
                        if(previous instanceof Integer)discoverSlot.set((Integer)previous);else discoverSlot.remove();
                    }
                }
            });
            hook(execute,new XC_MethodHook(){
                @Override protected void beforeHookedMethod(MethodHookParam call) {
                    if(!sdkObservationOpen())return;
                    Integer slot=discoverSlot.get();boolean sending=false;if(slot==null){slot=sendSlot.get();sending=true;}if(slot==null)return;
                    call.setObjectExtra("GT8_HTTP_SEND",Boolean.valueOf(sending));
                    try{call.setObjectExtra("GT8_HTTP_SLOT",slot);emit(sending?"SEND_HTTP_ENTER":"DISCOVER_HTTP_ENTER","slot="+slot);}
                    catch(Throwable ignored){/* No request fields are inspected. */}
                }
                @Override protected void afterHookedMethod(MethodHookParam call) {
                    Object marker=call.getObjectExtra("GT8_HTTP_SLOT");
                    boolean sending=Boolean.TRUE.equals(call.getObjectExtra("GT8_HTTP_SEND"));
                    if(!(marker instanceof Integer)||!sdkObservationOpen())return;
                    try {
                        if(call.hasThrowable())emit(sending?"SEND_HTTP_RETURN":"DISCOVER_HTTP_RETURN","slot="+marker+" result=THREW"+failureFields(call.getThrowable()));
                        else if(response.isInstance(call.getResult()))emit(sending?"SEND_HTTP_RETURN":"DISCOVER_HTTP_RETURN","slot="+marker+" result=RESPONSE code="+DiscoverLogic.status(status.getInt(call.getResult())));
                        else emit(sending?"SEND_HTTP_RETURN":"DISCOVER_HTTP_RETURN","slot="+marker+" result=OTHER");
                    }catch(Throwable ignored){emit(sending?"SEND_HTTP_RETURN":"DISCOVER_HTTP_RETURN","slot="+marker+" result=UNAVAILABLE");}
                }
            });
            emit("DISCOVER_OBSERVATION_READY","kind=READONLY");
        }
        boolean sdkObservationOpen(){return !stopped&&SystemClock.elapsedRealtime()<deadline;}
        String failureFields(Throwable failure){
            return " kind="+DiscoverLogic.error(failure)+" tls="+DiscoverLogic.tlsKind(failure)+" cause="+DiscoverLogic.causeKind(failure)+" reason="+DiscoverLogic.tlsReason(failure);
        }
        void probeNative(){
            if(!active())return;
            emit("APP_NATIVE_PROBE_STARTED","kind=READONLY");
            try {
                Class<?> manager=Class.forName("android.os.ServiceManager",false,null);
                Method declared=manager.getDeclaredMethod("isDeclared",String.class);
                declared.setAccessible(true);
                try {
                    Object value=declared.invoke(null,HookLogic.INSTANCE);
                    if(active())emit("APP_NATIVE_DECLARATION","result="+
                            (Boolean.TRUE.equals(value)?"TRUE":Boolean.FALSE.equals(value)?"FALSE":"UNAVAILABLE"));
                }catch(Throwable ignored){if(active())emit("APP_NATIVE_DECLARATION","result=UNAVAILABLE");}
                if(!active())return;
                Method check=manager.getDeclaredMethod("checkService",String.class);
                check.setAccessible(true);
                String outcome=ProbeLogic.inspect(active(),SystemClock.elapsedRealtime(),deadline,()->{
                    final Object value;
                    try{value=check.invoke(null,HookLogic.INSTANCE);}
                    catch(InvocationTargetException cause){
                        if(cause.getCause() instanceof SecurityException)throw (SecurityException)cause.getCause();
                        throw cause;
                    }
                    if(!(value instanceof IBinder))return null;
                    final IBinder binder=(IBinder)value;
                    return new HookLogic.BinderView(){
                        public boolean alive(){return binder.isBinderAlive();}
                        public String descriptor()throws Exception{return binder.getInterfaceDescriptor();}
                        public Object value(){return binder;}
                    };
                });
                if(active())emit("APP_NATIVE_PROBE_RESULT","result="+outcome);
                if(BuildVariant.BINDER&&active()&&"REAL_BINDER_VERIFIED".equals(outcome)){
                    emit("APP_COMPAT_PROBE_STARTED","kind=READONLY");
                    diagnosticLookup.set(Boolean.TRUE);
                    try {
                        Method wait=manager.getDeclaredMethod("waitForDeclaredService",String.class);
                        wait.setAccessible(true);
                        Object answer=wait.invoke(null,HookLogic.INSTANCE);
                        String result="NULL";
                        if(answer instanceof IBinder){
                            IBinder binder=(IBinder)answer;
                            result=!binder.isBinderAlive()?"REAL_BINDER_DEAD":
                                HookLogic.DESCRIPTOR.equals(binder.getInterfaceDescriptor())?"REAL_BINDER_VERIFIED":"DESCRIPTOR_MISMATCH";
                        }
                        if(active())emit("APP_COMPAT_PROBE_RESULT","result="+result);
                    }catch(Throwable ignored){if(active())emit("APP_COMPAT_PROBE_RESULT","result=LOOKUP_ERROR");}
                    finally{diagnosticLookup.remove();}
                }
            }catch(Throwable ignored){if(active())emit("APP_NATIVE_PROBE_RESULT","result=LOOKUP_ERROR");}
        }
        String lookupOrigin(){return Boolean.TRUE.equals(diagnosticLookup.get())?"DIAGNOSTIC":"APP";}
        String failureReason(Throwable failure){
            String message=failure.getMessage();
            for(String code:new String[]{"DEADLINE","EXPIRED","APK_SIZE","APK_CHANGED","APK_HASH","APK_SPLITS",
                    "LOADER_TYPE","DEX_ELEMENTS","DEX_MISSING","DEX_NAME","DEX_ENTRIES","DEX_SOURCE",
                    "CLASS_BUDGET","CLASS_SOURCE_AMBIGUOUS","GETTER_SIGNATURE","REGISTRY_SIGNATURE",
                    "STATUS_SIGNATURE","CALLBACK_SIGNATURE","TASK_SIGNATURE","SDK_BIND_SIGNATURE","DISCOVER_SIGNATURE","NO_HANDLE"})if(code.equals(message))return code;
            if(failure instanceof ClassNotFoundException)return "CLASS_UNAVAILABLE";
            if(failure instanceof ReflectiveOperationException)return "REFLECTION_UNAVAILABLE";
            return "IDENTITY_SOURCE_OR_INSTALL";
        }
        void emitCritical(String event,String fields){
            if(criticalLogs.incrementAndGet()>32)return;
            try{Log.i("GT8ProBridge","GT8BRIDGE_V1 event="+event+" process="+("com.google.android.gms".equals(pkg)?"GMS":"MOSEY")+" "+fields);}catch(Throwable ignored){}
        }
        void emit(String event,String fields){
            if(logs.incrementAndGet()>512)return;
            try{
                String line="GT8BRIDGE_V1 event="+event+" process="+
                        ("com.google.android.gms".equals(pkg)?"GMS":"MOSEY")+" "+fields;
                Log.i("GT8ProBridge",line);XposedBridge.log(line);
            }catch(Throwable ignored){/* No diagnostic failure escapes into the host process. */}
        }
        void stop(){
            synchronized(lock){
                stopped=true;armed=false;nativeArmed=false;
                nativeVersionHooks.clear();discoverThreads.clear();sendThreads.clear();receiveCallbacks.clear();synchronized(tlsObserved){tlsObserved.clear();}synchronized(sendCalls){sendCalls.clear();}sendTasks.clear();discoverTasks.clear();
                for(int i=handles.size()-1;i>=0;i--)try{handles.get(i).unhook();}catch(Throwable ignored){}
                handles.clear();
            }
            workers.shutdownNow();
        }
    }
}
