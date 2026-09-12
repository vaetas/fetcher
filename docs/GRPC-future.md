# gRPC (future)

gRPC requires a separate execution model (unary and streaming) via `grpc-swift-2`.

Do not route gRPC through `URLSession`. Add `GRPCRequestRecord` and
`GRPCRequestExecutor` when this protocol is implemented.
