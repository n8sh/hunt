import std.stdio;

import hunt.util.exception;
import hunt.util.UnitTest;
import hunt.logging;

import test.BigIntegerTest;
import test.LinkedBlockingQueueTest;
import test.TaskTest;
import test.ThreadPoolExecutorTest;

void main()
{
	// testUnits!(BigIntegerTest);
	// testTask();
	// testUnits!(LinkedBlockingQueueTest);
	 testUnits!(ThreadPoolExecutorTest);
}
