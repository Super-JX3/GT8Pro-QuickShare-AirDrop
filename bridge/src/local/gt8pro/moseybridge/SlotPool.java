package local.gt8pro.moseybridge;
import java.util.IdentityHashMap;
final class SlotPool {
 private final int limit;
 private final IdentityHashMap<Object,Integer> slots=new IdentityHashMap<>();
 SlotPool(int limit){if(limit<1||limit>32)throw new IllegalArgumentException();this.limit=limit;}
 synchronized int acquire(Object owner){
  if(owner==null)return 0;Integer prior=slots.get(owner);if(prior!=null)return prior;
  if(slots.size()>=limit)return 0;
  for(int id=1;id<=limit;id++)if(!slots.containsValue(id)){slots.put(owner,id);return id;}
  return 0;
 }
 synchronized void release(Object owner){slots.remove(owner);}
 synchronized int size(){return slots.size();}
 synchronized void clear(){slots.clear();}
}
