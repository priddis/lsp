package java.util;

import java.util.function.Consumer;
import java.util.function.Predicate;
import java.util.function.UnaryOperator;
import jdk.internal.access.SharedSecrets;
import jdk.internal.util.ArraysSupport;

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

    private static final Object[] DEFAULTCAPACITY_EMPTY_ELEMENTDATA = {};
    transient Long[] elementData; // non-private to simplify nested class access

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

    public void trimToSize() {
        modCount++;
        if (size < elementData.length) {
              ? EMPTY_ELEMENTDATA
              : Arrays.copyOf(elementData, size);
        }
    }

    public void newTestMethod() {


    }
}


