package local.gt8pro.moseybridge;
public final class SlotPoolTest {
 static int n;static void check(boolean v){n++;if(!v)throw new AssertionError(n);}
 public static void main(String[]a){for(int cap:new int[]{4,8}){
  SlotPool p=new SlotPool(cap);Object[] owners=new Object[cap];
  for(int i=0;i<cap;i++){owners[i]=new Object();check(p.acquire(owners[i])==i+1);check(p.acquire(owners[i])==i+1);}
  check(p.acquire(new Object())==0);check(p.size()==cap);
  p.release(owners[1]);Object replacement=new Object();check(p.acquire(replacement)==2);check(p.size()==cap);
  p.release(new Object());check(p.size()==cap);p.clear();check(p.size()==0);
  for(int i=0;i<10000;i++){Object owner=new Object();check(p.acquire(owner)==1);p.release(owner);check(p.size()==0);}
  check(p.acquire(null)==0);
  Object x=new String("same"),y=new String("same");check(p.acquire(x)==1);check(p.acquire(y)==2);check(p.size()==2);p.release(x);check(p.acquire(y)==2);
 }System.out.println("REUSABLE_SLOT_POOL_CHECKS_PASS="+n);}
}
