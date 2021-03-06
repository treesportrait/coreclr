// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

/*=============================================================================
**
**
**
** Purpose: Wrapper that is converted to a variant with VT_ERROR.
**
**
=============================================================================*/

namespace System.Runtime.InteropServices {
   
    using System;

    [Serializable]
    public sealed class ErrorWrapper
    {
        public ErrorWrapper(int errorCode)
        {
            m_ErrorCode = errorCode;
        }

        public ErrorWrapper(Object errorCode)
        {
            if (!(errorCode is int))
                throw new ArgumentException(Environment.GetResourceString("Arg_MustBeInt32"), nameof(errorCode));
            m_ErrorCode = (int)errorCode;
        }        

        public ErrorWrapper(Exception e)
        {
            m_ErrorCode = Marshal.GetHRForException(e);
        }

        public int ErrorCode 
        {
            get 
            {
                return m_ErrorCode;
            }
        }

        private int m_ErrorCode;
    }
}
