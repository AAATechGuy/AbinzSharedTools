using System;

namespace ABTests;

public static class ObjectABTester
{
    public static ABTestResult<TInput, TResult> RunABTest<TInput, TResult>(
        TInput methodParam,
        Func<TInput, TResult> method1,
        Func<TInput, TResult> method2,
        Func<TResult, TResult, bool> resultComparer,
        Func<Exception, Exception, bool> exComparer)
    {
        TResult resultA = default, resultB = default;
        Exception exA = null, exB = null;
        try
        {
            resultA = method1(methodParam);
        }
        catch (Exception ex)
        {
            exA = ex;
        }

        try
        {
            resultB = method2(methodParam);
        }
        catch (Exception ex)
        {
            exB = ex;
        }

        ABTestResultMismatchType mismatchType = ABTestResultMismatchType.NoMismatch;

        if (!resultComparer(resultA, resultB))
        {
            mismatchType = ABTestResultMismatchType.ResultMismatch;
        }

        if (exA != null || exB != null)
        {
            if (exA != null && exB != null)
            {
                if (!exComparer(exA, exB))
                {
                    mismatchType = ABTestResultMismatchType.ExceptionMismatch;
                }
            }
            else if (exA != null)
            {
                mismatchType = ABTestResultMismatchType.ExceptionExpected;
            }
            else // exA == null
            {
                mismatchType = ABTestResultMismatchType.ExceptionNotExpected;
            }
        }

        if (mismatchType != ABTestResultMismatchType.NoMismatch)
        {
            return new ABTestResult<TInput, TResult>()
            {
                MismatchType = mismatchType,
                Input = methodParam,
                ResultA = resultA,
                ResultB = resultB,
                ExA = exA,
                ExB = exB
            };
        }

        return null;
    }
}

public class ABTestResult<TInput, TResult>
{
    public ABTestResultMismatchType MismatchType;
    public TInput Input;
    public TResult ResultA;
    public TResult ResultB;
    public Exception ExA;
    public Exception ExB;
}

public enum ABTestResultMismatchType
{
    NoMismatch,
    ResultMismatch,
    ExceptionMismatch,
    ExceptionExpected,
    ExceptionNotExpected
}
