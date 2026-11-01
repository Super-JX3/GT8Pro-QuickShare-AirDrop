package local.gt8pro.moseybridge;
public final class ReceiveFixtureTest {
 static int checks;
 static void c(int count,String name,Long size,String type,String sender,String want){checks++;String got=ReceiveFixtureLogic.classify(count,name,size,type,sender);if(!want.equals(got))throw new AssertionError(checks+":"+got);}
 public static void main(String[]args){
 String n="GT8Pro-AirDrop-082-MacToPhone.txt",m="GT8Pro Test Mac",t="public.plain-text";
 c(1,n,8192L,t,m,"MATCH");c(1,n,8192L,t,"GT8Pro Test Sender","MATCH");
 for(int k:new int[]{-1,0,2,100})c(k,n,8192L,t,m,"NOT_SINGLE_FILE");
 for(String x:new String[]{null,"personal.txt","GT8Pro-AirDrop-082-MacToPhone.txt/","../"+n,n+".exe"})c(1,x,8192L,t,m,"NAME_MISMATCH");
 for(Long x:new Long[]{null,-1L,0L,8191L,8193L,Long.MAX_VALUE})c(1,n,x,t,m,"SIZE_MISMATCH");
 for(String x:new String[]{null,"","public.text\n","text/plain","x".repeat(129)})c(1,n,8192L,x,m,"TYPE_UNCONFIRMED");
 c(1,n,8192L,"public.folder",m,"FOLDER");
 for(String x:new String[]{null,"Other Mac",m+" ","Other Test Phone"})c(1,n,8192L,t,x,"SENDER_MISMATCH");
 System.out.println("RECEIVE_FIXTURE_ADMISSION_CHECKS_PASS="+checks);
 }
}
