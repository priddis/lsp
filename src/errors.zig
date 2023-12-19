
pub const UnrecoverableError = jslp_error || error{OutOfMemory, Unexpected, BrokenPipe, IsDir, SystemResources, AccessDenied, InputOutput, OperationAborted, WouldBlock, ConnectionResetByPeer, ConnectionTimedOut, NotOpenForReading, SocketNotConnected, EndOfStream, NetNameDeleted, };

const jslp_error = error {
    CouldNotParseHeader,
    CouldNotParseRequest,
    CouldNotSendResponse,
};


