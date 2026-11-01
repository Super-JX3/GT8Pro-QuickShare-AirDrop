package local.gt8pro.moseybridge;
import java.net.*;import javax.net.ssl.*;
public final class TransportMetadataTest{
 static int n;static void check(boolean b){n++;if(!b)throw new AssertionError("metadata "+n);}
 public static void main(String[] args)throws Exception{
  check(DiscoverLogic.protocols(new String[]{"TLSv1.3"}).equals("TLS13"));check(DiscoverLogic.protocols(new String[]{"TLSv1.2"}).equals("TLS12"));check(DiscoverLogic.protocols(new String[]{"TLSv1.2","TLSv1.3"}).equals("TLS13_TLS12"));
  for(String[] bad:new String[][]{null,new String[0],new String[9]})check(DiscoverLogic.protocols(bad).equals("UNAVAILABLE"));
  for(String[] bad:new String[][]{{"TLSv1.3","TLSv1.3"},{"TLSv1.1"},{"PRIVATE_VALUE"},{null}})check(DiscoverLogic.protocols(bad).equals("OTHER"));
  check(DiscoverLogic.addressKind(null).equals("NONE"));check(DiscoverLogic.addressKind(InetAddress.getByAddress(new byte[]{127,0,0,1})).equals("LOOPBACK"));check(DiscoverLogic.addressKind(InetAddress.getByAddress(new byte[]{0,0,0,0})).equals("UNSPECIFIED"));check(DiscoverLogic.addressKind(InetAddress.getByAddress(new byte[]{(byte)192,0,2,1})).equals("IPV4"));
  byte[] ip=new byte[16];ip[0]=(byte)0xfe;ip[1]=(byte)0x80;ip[15]=1;check(DiscoverLogic.addressKind(InetAddress.getByAddress(ip)).equals("IPV6_LINK_LOCAL"));ip[0]=0x20;ip[1]=1;check(DiscoverLogic.addressKind(InetAddress.getByAddress(ip)).equals("IPV6_OTHER"));
  check(DiscoverLogic.tlsReason(new SSLException("connection closed")).equals("CONNECTION_CLOSED"));check(DiscoverLogic.tlsReason(new SSLException("connection closed by peer")).equals("PEER_CLOSED"));check(DiscoverLogic.tlsReason(new SSLException("unexpected EOF")).equals("EOF"));
  System.out.println("TRANSPORT_METADATA_CHECKS_PASS="+n);
 }
}
