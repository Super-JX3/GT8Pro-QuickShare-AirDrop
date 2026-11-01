package local.gt8pro.moseybridge;

import java.io.*;
import java.net.*;
import java.security.cert.CertificateException;
import java.util.concurrent.CancellationException;
import javax.net.ssl.*;

/** Fixed enums only. TLS messages are bounded and matched in memory; never exported. Address objects are classified in memory; no address strings, header, name, or body exports. */
public final class DiscoverLogic {
    private DiscoverLogic() {}
    public static String status(int code) {
        return code>=100&&code<=599?Integer.toString(code):"OTHER";
    }
    public static String error(Throwable failure) {
        if(failure instanceof CancellationException)return "CANCELLED";
        if(failure instanceof SecurityException)return "SECURITY";
        if(failure instanceof SocketTimeoutException)return "TIMEOUT";
        if(failure instanceof CertificateException)return "CERTIFICATE";
        if(failure instanceof SSLException)return "TLS";
        if(failure instanceof NoRouteToHostException)return "NO_ROUTE";
        if(failure instanceof ConnectException)return "CONNECT";
        if(failure instanceof UnknownHostException)return "DNS";
        if(failure instanceof InterruptedIOException)return "INTERRUPTED_IO";
        if(failure instanceof IOException)return "IO";
        return "OTHER";
    }
    public static String tlsKind(Throwable failure) {
        if(failure instanceof SSLPeerUnverifiedException)return "PEER_UNVERIFIED";
        if(failure instanceof SSLHandshakeException)return "HANDSHAKE";
        if(failure instanceof SSLProtocolException)return "PROTOCOL";
        return failure instanceof SSLException?"GENERIC":"NONE";
    }
    public static String causeKind(Throwable failure) {
        if(failure==null)return "NONE";
        Throwable cause=failure.getCause();
        return cause==null||cause==failure?"NONE":error(cause);
    }
    public static String tlsReason(Throwable failure) {
        if(!(failure instanceof SSLException))return "NONE";
        Throwable current=failure;String fallback="UNCLASSIFIED";
        java.util.Set<Throwable> seen=java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<Throwable,Boolean>());
        for(int i=0;i<6&&current!=null&&seen.add(current);i++){
            String raw=current.getMessage();
            if(raw!=null&&raw.length()<=1024){
                String m=raw.toUpperCase(java.util.Locale.ROOT);
                if(m.contains("PROTOCOL_VERSION")||m.contains("PROTOCOL VERSION")||m.contains("UNSUPPORTED_PROTOCOL"))return "PROTOCOL_VERSION";
                if(m.contains("CERTIFICATE_VERIFY_FAILED")||m.contains("CERTIFICATE VERIFY FAILED")||m.contains("BAD_CERTIFICATE")||m.contains("CERTIFICATE_UNKNOWN"))return "CERTIFICATE";
                if(m.contains("CERTIFICATE_REQUIRED")||m.contains("CERTIFICATE REQUIRED"))return "CERTIFICATE_REQUIRED";
                if(m.contains("NO_SHARED_CIPHER")||m.contains("NO CIPHER")||m.contains("NO_CIPHERS_AVAILABLE"))return "CIPHER";
                if(m.contains("HANDSHAKE_FAILURE")||m.contains("HANDSHAKE FAILURE"))return "HANDSHAKE_ALERT";
                if(m.contains("CONNECTION RESET")||m.contains("ECONNRESET"))return "RESET";
                if(m.contains("TIMED OUT")||m.contains("ETIMEDOUT"))return "TIMEOUT";
                if(m.contains("CONNECTION CLOSED BY PEER")||m.contains("PEER CLOSED"))return "PEER_CLOSED";
                if(m.contains("CONNECTION CLOSED")||m.contains("SSL_ERROR_ZERO_RETURN"))return "CONNECTION_CLOSED";
                if(m.contains("UNEXPECTED EOF"))return "EOF";
                if(m.contains("BROKEN PIPE")||m.contains("EPIPE"))return "BROKEN_PIPE";
                if(m.contains("SOFTWARE CAUSED CONNECTION ABORT")||m.contains("ECONNABORTED"))return "ABORTED";
                if(m.contains("WRONG_VERSION_NUMBER")||m.contains("WRONG VERSION NUMBER"))return "RECORD_VERSION";
                if(m.contains("UNEXPECTED_MESSAGE")||m.contains("UNEXPECTED_RECORD"))return "UNEXPECTED_RECORD";
                if(m.contains("BAD_RECORD_MAC")||m.contains("BAD RECORD MAC"))return "RECORD_MAC";
                if(m.contains("LENGTH_TOO_SHORT")||m.contains("PACKET_LENGTH_TOO_LONG")||m.contains("BAD_PACKET_LENGTH"))return "RECORD_LENGTH";
                if(m.contains("I/O ERROR DURING SYSTEM CALL"))fallback="SYSCALL_IO";
                if(m.contains("READ ERROR")||m.contains("READ FAILED"))fallback="READ_IO";
                if(m.contains("WRITE ERROR")||m.contains("WRITE FAILED"))fallback="WRITE_IO";
            }
            current=current.getCause();
        }
        return fallback;
    }
    public static String protocols(String[] values){
        if(values==null||values.length<1||values.length>8)return "UNAVAILABLE";
        boolean a=false,b=false;
        for(String v:values){if("TLSv1.3".equals(v)){if(a)return "OTHER";a=true;}else if("TLSv1.2".equals(v)){if(b)return "OTHER";b=true;}else return "OTHER";}
        return a&&b?"TLS13_TLS12":a?"TLS13":b?"TLS12":"OTHER";
    }
    public static String addressKind(java.net.InetAddress address){
        if(address==null)return "NONE";
        if(address.isLoopbackAddress())return "LOOPBACK";
        if(address.isAnyLocalAddress())return "UNSPECIFIED";
        if(address instanceof java.net.Inet6Address)return address.isLinkLocalAddress()?"IPV6_LINK_LOCAL":"IPV6_OTHER";
        return address instanceof java.net.Inet4Address?"IPV4":"OTHER";
    }
    public static String phase(StackTraceElement[] stack) {
        boolean dns=false,connect=false,read=false,tlsRead=false,wait=false;
        if(stack==null||stack.length>256)return "UNAVAILABLE";
        for(StackTraceElement frame:stack) {
            if(frame==null)continue;
            String c=frame.getClassName(),m=frame.getMethodName();
            boolean tls=c.startsWith("com.android.org.conscrypt.")||c.startsWith("org.conscrypt.");
            if(tls&&(m.equals("SSL_do_handshake")||m.equals("doHandshake")||m.equals("startHandshake")))return "TLS_HANDSHAKE";
            if(tls&&(m.equals("SSL_read")||m.equals("read")||m.equals("readFromSocket")))tlsRead=true;
            if((c.equals("java.net.Inet6AddressImpl")&&m.equals("lookupAllHostAddr"))
                    ||(c.equals("java.net.InetAddress")&&m.startsWith("getAllByName")))dns=true;
            if((c.equals("java.net.Socket")||c.equals("libcore.io.IoBridge")||c.equals("libcore.io.Linux")||c.equals("android.system.Os"))
                    &&(m.equals("connect")||m.equals("connectErrno")))connect=true;
            if((c.equals("java.net.SocketInputStream")&&(m.equals("socketRead0")||m.equals("read")))
                    ||((c.equals("libcore.io.Linux")||c.equals("libcore.io.IoBridge"))&&(m.equals("read")||m.equals("recvfrom"))))read=true;
            if((c.equals("java.lang.Object")&&m.equals("wait"))||(c.equals("java.lang.Thread")&&m.equals("sleep"))
                    ||((c.equals("jdk.internal.misc.Unsafe")||c.equals("sun.misc.Unsafe"))&&m.equals("park")))wait=true;
        }
        return dns?"DNS":connect?"CONNECT":tlsRead?"TLS_READ":read?"READ":wait?"WAIT":"OTHER";
    }
}
