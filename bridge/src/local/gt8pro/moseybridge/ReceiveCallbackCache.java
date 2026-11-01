package local.gt8pro.moseybridge;

import java.util.WeakHashMap;

/** Holds the first observed callback for a collector, not a process-wide callback. */
final class ReceiveCallbackCache {
    private final WeakHashMap<Object,Object> callbacks = new WeakHashMap<>();
    synchronized void remember(Object collector,Object callback) {
        if(collector!=null && callback!=null && !callbacks.containsKey(collector)) callbacks.put(collector,callback);
    }
    synchronized Object get(Object collector) { return callbacks.get(collector); }
    static boolean recoverable(int code,boolean terminal,Object shared,Object saved,Object remembered) {
        return code==1006 && terminal && shared==null && saved==null && remembered!=null;
    }
    synchronized void remove(Object collector) { callbacks.remove(collector); }
    synchronized void clear() { callbacks.clear(); }
}
