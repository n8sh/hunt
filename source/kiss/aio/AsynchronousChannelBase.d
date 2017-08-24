/*
 * KISS - A refined core library for dlang
 *
 * Copyright (C) 2015-2017  Shanghai Putao Technology Co., Ltd
 *
 * Developer: HuntLabs
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module kiss.aio.AsynchronousChannelBase;

import kiss.aio.AsynchronousChannelThreadGroup;
import kiss.aio.AsynchronousChannelSelector;
import kiss.aio.AsynchronousSocketChannel;
import kiss.aio.AsynchronousSelectionKey;
import kiss.aio.ByteBuffer;
import kiss.aio.CompletionHandle;
import kiss.aio.Event;
import kiss.aio.task;
import kiss.aio.WriteBufferData;
import kiss.util.Common;

import core.stdc.errno;

import std.socket;
import std.stdio;
import std.experimental.logger;



class AsynchronousChannelBase : CompletionHandle
{
	public
	{
		this(AsynchronousChannelThreadGroup group, AsynchronousChannelSelector sel)
		{
			_selector = sel;
			_group = group;
			_writeBufferQueue = new WriteBufferDataQueue();

		}

		void setOpen(bool b)
		{
			_isOpen = b;
		}
		
		bool isOpen()
		{
			return _isOpen;
		}
		
		socket_t getFd()
		{
			return _socket.handle;
		}

		void close()
		{
			_isReadyClose = true;
		}

		AsynchronousChannelThreadGroup getGroup()
		{
			return _group;
		}

		void read(ByteBuffer buffer, ReadCompletionHandle handle, void* attachment)
		{
			register(AIOEventType.OP_READED,  cast(void*)handle, attachment, buffer);
		}

		void write(string buffer, WriteCompletionHandle handle, void* attachment)
		{
			ByteBuffer b = ByteBuffer.allocate(cast(int)(buffer.length + 1));
			b.put(cast(byte[])buffer);
			write(b, handle, attachment);
		}

		void write(ByteBuffer buffer, WriteCompletionHandle handle, void* attachment)
		{
			WriteBufferData data = new WriteBufferData();
			data.buffer = buffer;
			data.handle = handle;
			data.attachment = attachment;

			synchronized (this)
			{
				bool empty = _writeBufferQueue.empty();
				_writeBufferQueue.enQueue(data);
				if (empty)
					registerWriteData(data);
			}
		}
		

		override void completed(AIOEventType eventType, void* attachment, void* p1 = null, void* p2 = null)
		{
			if (eventType == AIOEventType.OP_ACCEPTED)
				_acceptHandle.acceptCompleted(attachment, cast(AsynchronousSocketChannel)p1);
			else if (eventType == AIOEventType.OP_CONNECTED)
			{
				_connectHandle.connectCompleted(attachment);
				unRegisterOp(AIOEventType.OP_CONNECTED);
			}
			else if (eventType == AIOEventType.OP_READED)
				_readHandle.readCompleted(attachment, cast(size_t)p1, cast(ByteBuffer)p2);
			else if (eventType == AIOEventType.OP_WRITEED)
			{
				synchronized (this)
				{
					ByteBuffer b = cast(ByteBuffer)p2;
					WriteBufferData data = _writeBufferQueue.front();
					data.handle.writeCompleted(attachment, cast(size_t)p1, b);
					_writeBufferQueue.deQueue();	
					if (!_writeBufferQueue.empty())
						registerWriteData(_writeBufferQueue.front());
					else 
					{
						//unRegisterOp OP_WRITEED when writelist is empty
						unRegisterOp(AIOEventType.OP_WRITEED);
					}
				}
			}
		}
    	override void failed(AIOEventType eventType, void* attachment)
		{
			if (eventType == AIOEventType.OP_ACCEPTED)
				_acceptHandle.acceptFailed(attachment);
			else if (eventType == AIOEventType.OP_CONNECTED)
			{
				_connectHandle.connectFailed(attachment);
				unRegisterOp(AIOEventType.OP_CONNECTED);
			}
			else if (eventType == AIOEventType.OP_READED)
			{
				_readHandle.readFailed(attachment);
				unRegisterOp(AIOEventType.OP_READED);
			}
			else if (eventType == AIOEventType.OP_WRITEED)
			{
				synchronized (this)
				{
					while (!_writeBufferQueue.empty())
					{
						WriteBufferData data = _writeBufferQueue.deQueue();
						(cast(WriteCompletionHandle)(data.handle)).writeFailed(data.attachment);
					}
					unRegisterOp(AIOEventType.OP_WRITEED);
				}
			}
		}


		public void unRegisterOp(AIOEventType ops)
		{
			int newOps = _intrestOps & ~ops;
			int newWriteAble = getReadWriteAble(newOps);
			_selector.modEvent(_key,  _socket.handle,  newWriteAble, getReadWriteAble(_intrestOps));
			_intrestOps = newOps;	
		}



		Socket socket()
		{
			return _socket;
		}

		void setSocket(Socket socket)
		{
			_socket = socket;
			_socket.blocking(false);
		}

		abstract int validOps();

		int intrestOps()
		{
			return _intrestOps;
		}



		bool onClose()
		{
			_selector.delEvent(_key , _socket.handle, EventType.NONE);
			_socket.close();
			setOpen(false);
			synchronized (this)
			{
				while (!_writeBufferQueue.empty())
				{
					WriteBufferData data = _writeBufferQueue.deQueue();
					(cast(WriteCompletionHandle)(data.handle)).writeFailed(data.attachment);
				}
			}

			return true;
		}

		bool isReadyClose()
		{
			return _isReadyClose;
		}
	}

	void addTask(bool MustInQueue = true)(AbstractTask task)
	{
		_selector.addTask!(MustInQueue)(task);
	}

	protected void register(int ops, void* handle, void* attchment, ByteBuffer obj = null)
    {
        if (!checkVailid(ops))
		{
            return ;
		}

        bool isNew = false;

        if (_intrestOps == 0 && _key is null)
        {
            _key = new AsynchronousSelectionKey();
            _key.selector(_selector);
            _key.channel(this);
            isNew = true;
        }

		if (ops == AIOEventType.OP_ACCEPTED) {
			_acceptHandle = cast(AcceptCompletionHandle)handle;
		}
		else if (ops == AIOEventType.OP_CONNECTED) {
			_connectHandle = cast(ConnectCompletionHandle)handle;
		}
		else if (ops == AIOEventType.OP_READED)
		{
			_readHandle = cast(ReadCompletionHandle)handle;
			_key._readBuffer = obj;
		}
		else if (ops == AIOEventType.OP_WRITEED)
		{
			_key._writeBuffer = obj;
		}
		
        _key.handle(cast(void*)this);
        _key.handleAttachment(attchment);


		
		if (isNew) {
            _selector.addEvent(_key,  _socket.handle,  getReadWriteAble(ops));
        }
        else {
			if (_intrestOps & ops)
				return;
			_selector.modEvent(_key,  _socket.handle,  getReadWriteAble(ops), getReadWriteAble(_intrestOps));
        }
        _intrestOps |= ops;

    }

	private int getReadWriteAble(int ops) {
		int ret = 0;
		if (ops & AIOEventType.OP_ACCEPTED || ops & AIOEventType.OP_READED)
			ret |= EventType.READ;
		if (ops & AIOEventType.OP_CONNECTED || ops & AIOEventType.OP_WRITEED)
			ret |= EventType.WRITE;
		return ret;
	}



	private void registerWriteData(WriteBufferData data)
	{	
		register(cast(int)AIOEventType.OP_WRITEED, cast(void*)this, data.attachment, data.buffer);
	}

	private bool checkVailid(int ops)
    {
        if (!isOpen())
        {
            log(LogLevel.info , "Channel was closed!!!");
            return false;
        }
		
        if ((ops & ~validOps()) != 0)
        {
            log(LogLevel.info , "Channel unsupport ops!!!",ops);
            return false;
        }
		
        return true;
    }

	protected
	{
		AsynchronousSelectionKey _key; 
		AsynchronousChannelSelector _selector;
		ByteBuffer _attachment;
		void* _handle;
		void* _handleAttachment;
		Socket _socket;
	}

	private
	{
		AcceptCompletionHandle _acceptHandle;
		ConnectCompletionHandle _connectHandle;
		ReadCompletionHandle _readHandle;

		ByteBuffer _readBuffer;
		ByteBuffer _writeBuffer;

		WriteBufferDataQueue _writeBufferQueue;
		AsynchronousChannelThreadGroup _group;
		bool _isOpen = false;
		bool _isReadyClose = false;
		int _intrestOps = 0;
	}

	
}
