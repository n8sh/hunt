module hunt.serialization.BinarySerializer;

import std.array : Appender;
import std.traits;
import hunt.serialization.Specify;


/**
 * 
 */
struct BinarySerializer {
    private {
        Appender!(ubyte[]) _buffer;
    }

    ubyte[] oArchive(T)(T val) if (!isArray!T && !isAssociativeArray!T) {
        Unqual!T copy = val;
        specify(this, copy);
        return _buffer.data();
    }

    ubyte[] oArchive(T)(const ref T val)
            if (!isDynamicArray!T && !isAssociativeArray!T && !isAggregateType!T) {
        T copy = val;
        specify(this, copy);
        return _buffer.data();
    }

    ubyte[] oArchive(T)(const(T)[] val) {
        auto copy = (cast(T[]) val).dup;
        specify(this, copy);
        return _buffer.data();
    }

    ubyte[] oArchive(K, V)(const(V[K]) val) {
        auto copy = cast(V[K]) val.dup;
        specify(this, copy);
        return _buffer.data();
    }

    void putUbyte(ref ubyte val) {
        _buffer.put(val);
    }

    void putClass(T)(T val) if (is(T == class)) {
        specifyClass(this, val);
    }

    void putRaw(ubyte[] val) {
        _buffer.put(val);
    }

    bool isNullObj() {
        return false;
    }

}
