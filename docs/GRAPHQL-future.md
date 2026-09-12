# GraphQL (future)

GraphQL request editing and execution will be added after REST V1 is stable.

Do not store GraphQL as a REST request with a magic body. Use a dedicated
`GraphQLRequestRecord` and `GraphQLRequestExecutor` that may reuse HTTP transport.
