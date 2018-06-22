public class Function {
    public static void test() {
        System.debug(Function.F.run.run());
    }

    public static final Funcs F = new Funcs();

    public class Funcs {
        public Func add = new AddFunc();
        public Func run = new RunFunc();
    }

    private class AddFunc extends Func {
        public AddFunc() {
            super(2);
        }

        public override Object execN(List<Object> args) {
            Integer a = (Integer)args.get(0);
            Integer b = (Integer)args.get(1);

            return a + b;
        }
    }

    private class RunFunc extends Func {
        public RunFunc() {
            super(0);
        }

        public override Object execN(List<Object> args) {
            System.debug('Test');

            return null;
        }
    }
}