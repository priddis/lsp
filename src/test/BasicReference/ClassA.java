package mypackage;
import mypackage.ClassB;

public class ClassA {

    ClassA() {

    }
    
    public int doThing() {
        var b = new ClassB();
        b.doMoreThings();
        return b;
    }

    public int doAnotherThing(ClassB p) {
        p.doMoreThings();
        ClassB d = new ClassB();
        return 0;
    }
}
