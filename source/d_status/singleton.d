module d_status.singleton;

@safe:

mixin template threadLocalSingleton()
{
    import std.format : f = format;

    static assert(is(typeof(this) == class));
    static assert(!is(typeof(this) == shared));

    private static typeof(this) tls_instance;

    static
    void createInstance()
    in (tls_instance is null)
    out (; tls_instance !is null)
    {
        try
        {
            tls_instance = new typeof(this)();
        }
        catch (Exception e)
        {
            enum string name = typeof(this).stringof;
            string msg = (() @trusted => e.toString)();
            assert(false, f!`Failed to create instance of singleton "%s": %s`(name, msg));
        }
    }

    static nothrow @nogc
    typeof(this) instance()
    in (tls_instance !is null, typeof(this).stringof ~ ".tls_instance is null")
        => tls_instance;

    static nothrow @nogc
    const(typeof(this)) constInstance()
        => instance;
}
