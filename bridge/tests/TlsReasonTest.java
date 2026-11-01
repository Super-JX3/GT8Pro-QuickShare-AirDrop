package local.gt8pro.moseybridge;
import javax.net.ssl.*;import java.io.*;
public final class TlsReasonTest{
 static int n;static void check(Throwable t,String want){n++;if(!DiscoverLogic.tlsReason(t).equals(want))throw new AssertionError("TLS reason "+n);}
 public static void main(String[] args)throws Exception{
  String[][] rows={{"tlsv1 alert protocol version","PROTOCOL_VERSION"},{"CERTIFICATE_VERIFY_FAILED","CERTIFICATE"},{"certificate required","CERTIFICATE_REQUIRED"},{"NO_SHARED_CIPHER","CIPHER"},{"sslv3 alert handshake failure","HANDSHAKE_ALERT"},{"Connection reset by peer","RESET"},{"Read timed out","TIMEOUT"},{"Connection closed by peer","PEER_CLOSED"},{"Broken pipe","BROKEN_PIPE"},{"ECONNABORTED","ABORTED"},{"WRONG_VERSION_NUMBER","RECORD_VERSION"},{"UNEXPECTED_RECORD","UNEXPECTED_RECORD"},{"BAD_RECORD_MAC","RECORD_MAC"},{"LENGTH_TOO_SHORT","RECORD_LENGTH"},{"I/O error during system call","SYSCALL_IO"},{"read failed","READ_IO"},{"write error","WRITE_IO"},{"PRIVATE_DEVICE_NAME_ABC","UNCLASSIFIED"}};
  for(var r:rows)check(new SSLHandshakeException(r[0]),r[1]);
  check(new IOException("connection reset"),"NONE");check(null,"NONE");check(new SSLHandshakeException(null),"UNCLASSIFIED");check(new SSLHandshakeException("x".repeat(1025)+"ECONNRESET"),"UNCLASSIFIED");
  var tls=new SSLHandshakeException("I/O error during system call");tls.initCause(new IOException("ECONNRESET"));check(tls,"RESET");
  var nested=new SSLHandshakeException("x");Throwable p=nested;for(int i=0;i<8;i++){var c=new IOException(i==7?"ECONNRESET":"x");p.initCause(c);p=c;}check(nested,"UNCLASSIFIED");
  var cycle=new SSLHandshakeException("x");var c=new IOException("x");cycle.initCause(c);c.initCause(cycle);check(cycle,"UNCLASSIFIED");
  System.out.println("TLS_REASON_CLASSIFICATION_CHECKS_PASS="+n);
 }
}
