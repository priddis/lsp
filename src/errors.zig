const std = @import("std");
pub const UnrecoverableError = jlava_error || error{
    OutOfMemory,
    Unexpected,
    BrokenPipe,
    IsDir,
    SystemResources,
    AccessDenied,
    InputOutput,
    OperationAborted,
    WouldBlock,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NotOpenForReading,
    SocketNotConnected,
    EndOfStream,
    NetNameDeleted,
};

const jlava_error = error{
    CouldNotParseHeader,
    CouldNotParseRequest,
    CouldNotSendResponse,
};

pub const IndexingError = error{
    ErrorDuringIndexing,
    OutOfMemory,
} || std.fs.File.OpenError;
