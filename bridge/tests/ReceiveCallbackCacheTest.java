package local.gt8pro.moseybridge;

public final class ReceiveCallbackCacheTest {
    static void check(boolean ok) { if(!ok) throw new AssertionError(); }
    public static void main(String[] args) {
        ReceiveCallbackCache c=new ReceiveCallbackCache();
        Object one=new Object(), two=new Object(), a=new Object(), b=new Object();
        c.remember(one,a); c.remember(one,b); c.remember(two,b);
        check(c.get(one)==a && c.get(two)==b);
        check(ReceiveCallbackCache.recoverable(1006,true,null,null,c.get(one)));
        check(!ReceiveCallbackCache.recoverable(1006,false,null,null,a));
        check(!ReceiveCallbackCache.recoverable(1005,true,null,null,a));
        check(!ReceiveCallbackCache.recoverable(1006,true,b,null,a));
        check(!ReceiveCallbackCache.recoverable(1006,true,null,b,a));
        check(!ReceiveCallbackCache.recoverable(1006,true,null,null,null));
        c.remove(one); check(c.get(one)==null && c.get(two)==b);
        c.clear(); check(c.get(two)==null);
        System.out.println("CALLBACK_RECOVERY_POLICY=PASS");
    }
}
