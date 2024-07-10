package java.util;

import java.util.function.Consumer;
import java.util.function.Predicate;
import java.util.function.UnaryOperator;
import jdk.internal.access.SharedSecrets;
import java.util.HashMap;

public class ArrayListSmall<E> extends AbstractList<E>
        implements List<E>, RandomAccess, Cloneable, java.io.Serializable
{
    @java.io.Serial
    private static final long serialVersionUID = 8683452581122892189L;

    /**
     * Default initial capacity.
     */
    private static final int DEFAULT_CAPACITY = 10;

    /**
     * Shared empty array instance used for empty instances.
     */
    private static final Object[] EMPTY_ELEMENTDATA = {};

    /**
     * Shared empty array instance used for default sized empty instances. We
     * distinguish this from EMPTY_ELEMENTDATA to know how much to inflate when
     * first element is added.
     */
    private static final Object[] DEFAULTCAPACITY_EMPTY_ELEMENTDATA = {};

    transient Object[] elementData; // non-private to simplify nested class access

    private int size;


    public ArrayList(Collection<? extends E> c, int paramb) {
        Object[] a = c.toArray();
        if (c.getClass() == ArrayList.class) {
                elementData = a;
        } else {
            // replace with empty array.
            trimToSize();
        }
        a = 3;
        hello(a);
        a.b(paramb);

    }

    public void newMethod() {

    }

    public void trimToSize() {
        newMethod();
        modCount++;
        if (size < elementData.length) {
              ? EMPTY_ELEMENTDATA
              : Arrays.copyOf(elementData, size);
        }
        final HashMap map = new HashMap<String, Long>();
        map.put("Hello", 3012L);
    }
}

