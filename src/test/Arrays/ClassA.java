package mypackage;
import mypackage.ClassB;

public class ClassA {

    ClassA() {

    }
    
    public int[] doThing() {
        var b = new ClassB();
        b.doMoreThings();
        int[] returning_array = {0, 0};
        return returning_array;
    }

    public ClassB[] doAnotherThing(ClassB p) {
        p.doMoreThings();
        ClassB b = new ClassB();
        ClassB[] d = { new ClassB()};
        return d;
    }
}
