## ADDED Requirements

### Requirement: Market buy requests include idempotency key
The `market_buy` function SHALL generate a unique `newClientOrderId` parameter for each request. The value MUST be a 32-character lowercase hexadecimal string generated from cryptographically secure random bytes.

#### Scenario: Market buy sends newClientOrderId
- **WHEN** a market buy request is made to Binance
- **THEN** the request params MUST include a `newClientOrderId` field with a 32-character hex string

#### Scenario: Each market buy has a unique key
- **WHEN** two market buy requests are made
- **THEN** each request MUST have a different `newClientOrderId` value

### Requirement: OCO sell requests include idempotency key
The `place_oco_sell` function SHALL generate a unique `listClientOrderId` parameter for each request. The value MUST be a 32-character lowercase hexadecimal string generated from cryptographically secure random bytes.

#### Scenario: OCO sell sends listClientOrderId
- **WHEN** an OCO sell request is made to Binance
- **THEN** the request params MUST include a `listClientOrderId` field with a 32-character hex string

#### Scenario: Each OCO sell has a unique key
- **WHEN** two OCO sell requests are made
- **THEN** each request MUST have a different `listClientOrderId` value

### Requirement: Market buy uses explicit HTTP timeouts
The `market_buy` function SHALL configure HTTP requests with a 10-second connect timeout and 30-second receive timeout.

#### Scenario: Market buy timeout configuration
- **WHEN** a market buy HTTP request is made (not via mock)
- **THEN** the request MUST use `connect_timeout: 10_000` and `receive_timeout: 30_000`

### Requirement: OCO sell uses explicit HTTP timeouts
The `place_oco_sell` function SHALL configure HTTP requests with a 10-second connect timeout and 60-second receive timeout.

#### Scenario: OCO sell timeout configuration
- **WHEN** an OCO sell HTTP request is made (not via mock)
- **THEN** the request MUST use `connect_timeout: 10_000` and `receive_timeout: 60_000`

### Requirement: Trading requests disable automatic retry
All signed trading HTTP requests SHALL disable Req's automatic retry mechanism.

#### Scenario: Retry disabled on trading requests
- **WHEN** any signed trading request is made via `post_signed`
- **THEN** the Req client MUST be configured with `retry: false`
