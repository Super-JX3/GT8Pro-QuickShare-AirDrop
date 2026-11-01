package local.gt8pro.moseybridge;
import java.io.*;
import java.net.*;
import java.security.cert.CertificateException;
import java.util.concurrent.CancellationException;
import javax.net.ssl.*;
public final class DiscoverTest {
 static int n;
 static void eq(Object a,Object b){n++;if(!a.equals(b))throw new AssertionError("Discover check "+n);}
 static StackTraceElement f(String c,String m){return new StackTraceElement(c,m,"unexported",1);}
 public static void main(String[] args) {
  eq(DiscoverLogic.error(new CancellationException("private")),"CANCELLED");
  eq(DiscoverLogic.error(new SocketTimeoutException("private")),"TIMEOUT");
  eq(DiscoverLogic.error(new SSLException("private")),"TLS");
  eq(DiscoverLogic.error(new CertificateException("private")),"CERTIFICATE");
  eq(DiscoverLogic.error(new NoRouteToHostException()),"NO_ROUTE");
  eq(DiscoverLogic.error(new ConnectException()),"CONNECT");
  eq(DiscoverLogic.error(new UnknownHostException()),"DNS");
  eq(DiscoverLogic.error(new InterruptedIOException()),"INTERRUPTED_IO");
  eq(DiscoverLogic.error(new IOException()),"IO");
  eq(DiscoverLogic.error(new SecurityException()),"SECURITY");
  eq(DiscoverLogic.error(new RuntimeException(){public String getMessage(){throw new AssertionError("must not inspect message");}}),"OTHER");
  eq(DiscoverLogic.status(200),"200");eq(DiscoverLogic.status(404),"404");eq(DiscoverLogic.status(99),"OTHER");eq(DiscoverLogic.status(600),"OTHER");
  eq(DiscoverLogic.phase(new StackTraceElement[]{f("libcore.io.Linux","read"),f("com.android.org.conscrypt.ConscryptFileDescriptorSocket","startHandshake")}),"TLS_HANDSHAKE");
  eq(DiscoverLogic.phase(new StackTraceElement[]{f("java.net.Socket","connect")}),"CONNECT");
  eq(DiscoverLogic.phase(new StackTraceElement[]{f("java.net.Inet6AddressImpl","lookupAllHostAddr")}),"DNS");
  eq(DiscoverLogic.phase(new StackTraceElement[]{f("com.android.org.conscrypt.NativeCrypto","SSL_read")}),"TLS_READ");
  eq(DiscoverLogic.phase(new StackTraceElement[]{f("java.net.SocketInputStream","read")}),"READ");
  eq(DiscoverLogic.phase(new StackTraceElement[]{f("java.lang.Object","wait")}),"WAIT");
  eq(DiscoverLogic.phase(new StackTraceElement[]{f("lookalike.java.net.Socket","connect")}),"OTHER");
  eq(DiscoverLogic.phase(new StackTraceElement[257]),"UNAVAILABLE");
  eq(DiscoverLogic.phase(null),"UNAVAILABLE");
  eq(DiscoverLogic.tlsKind(new SSLHandshakeException("private")),"HANDSHAKE");
  eq(DiscoverLogic.tlsKind(new SSLProtocolException("private")),"PROTOCOL");
  eq(DiscoverLogic.tlsKind(new SSLPeerUnverifiedException("private")),"PEER_UNVERIFIED");
  eq(DiscoverLogic.tlsKind(new SSLException("private")),"GENERIC");
  eq(DiscoverLogic.tlsKind(new IOException()),"NONE");
  eq(DiscoverLogic.causeKind(new SSLException("private",new SocketTimeoutException("private"))),"TIMEOUT");
  eq(DiscoverLogic.causeKind(new SSLException("private")),"NONE");
  System.out.println("DISCOVER_CLASSIFICATION_CHECKS_PASS="+n);
 }
}
