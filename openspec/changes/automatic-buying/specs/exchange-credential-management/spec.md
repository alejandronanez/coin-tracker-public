## ADDED Requirements

### Requirement: Vault module for field-level encryption

The system SHALL provide a `CoinTracker.Vault` GenServer that configures Cloak with AES-256-GCM encryption
using a key derived from `SECRET_KEY_BASE`. The Vault SHALL be started in the application supervision tree.

#### Scenario: Vault starts with application
- **WHEN** the application starts
- **THEN** the `CoinTracker.Vault` GenServer is running
- **AND** it is configured with an AES-256-GCM cipher using a key derived from `SECRET_KEY_BASE`

#### Scenario: Encrypted Ecto types are available
- **WHEN** a schema field uses `CoinTracker.Vault.Encrypted.Binary` as its type
- **THEN** the value is encrypted with AES-256-GCM before writing to the database
- **AND** the value is decrypted transparently when read from the database

### Requirement: ExchangeCredential schema with encrypted fields

The system SHALL store exchange API credentials in an `exchange_credentials` table with encrypted `api_key`
and `api_secret` fields. Each credential belongs to a user and is scoped to a specific exchange.

#### Scenario: Creating a credential
- **WHEN** a user provides a valid API key, API secret, and exchange
- **THEN** the system stores the credential with `api_key` and `api_secret` encrypted at rest
- **AND** stores a SHA-256 hash of the `api_key` for lookup without decryption
- **AND** associates the credential with the user

#### Scenario: Credential uniqueness per exchange
- **WHEN** a user attempts to create a second credential for the same exchange
- **THEN** the system rejects the credential with a validation error
- **AND** suggests updating the existing credential instead

#### Scenario: Reading a credential decrypts transparently
- **WHEN** the system loads an `ExchangeCredential` from the database
- **THEN** `api_key` and `api_secret` are available as plaintext strings in the struct
- **AND** the database columns contain only encrypted binary data

#### Scenario: Deleting a credential
- **WHEN** a user deletes an exchange credential
- **THEN** the credential row is permanently removed from the database
- **AND** no encrypted key material remains

### Requirement: Credential CRUD in Accounts context

The `Accounts` context SHALL expose functions for managing exchange credentials, scoped to the requesting user.

#### Scenario: Listing credentials for a user
- **WHEN** `Accounts.list_exchange_credentials(user_id)` is called
- **THEN** it returns all credentials for that user
- **AND** each credential shows `exchange`, `label`, `api_key_prefix` (first 8 chars), and `last_used_at`
- **AND** does NOT expose full `api_key` or `api_secret` in the list

#### Scenario: Getting a credential for trading
- **WHEN** `Accounts.get_exchange_credential(user_id, :binance_spot)` is called
- **AND** the user has a Binance credential stored
- **THEN** it returns the full credential with decrypted `api_key` and `api_secret`

#### Scenario: Getting a credential that doesn't exist
- **WHEN** `Accounts.get_exchange_credential(user_id, :binance_spot)` is called
- **AND** the user has no Binance credential
- **THEN** it returns `nil`

#### Scenario: Updating last_used_at after a trade
- **WHEN** a credential is used to place an order
- **THEN** the `last_used_at` timestamp is updated to the current time

### Requirement: Credential management UI

The system SHALL provide a settings page where users can add, view, and remove exchange API credentials.

#### Scenario: Adding a new credential
- **WHEN** the user navigates to the credential settings page
- **AND** enters a Binance API key and secret
- **AND** optionally provides a label
- **THEN** the credential is encrypted and stored
- **AND** the user sees a success message
- **AND** the key is displayed as masked (showing only prefix)

#### Scenario: Viewing existing credentials
- **WHEN** the user navigates to the credential settings page
- **AND** has stored credentials
- **THEN** each credential shows: exchange name, label, key prefix (first 8 chars), and last used date
- **AND** full keys are never displayed

#### Scenario: Removing a credential
- **WHEN** the user clicks "Remove" on an existing credential
- **AND** confirms the action
- **THEN** the credential is permanently deleted
- **AND** the user sees a confirmation message

#### Scenario: Guidance on API key permissions
- **WHEN** the user is on the credential creation form
- **THEN** the page displays guidance text explaining:
- **AND** the key must have "Enable Spot Trading" permission on Binance
- **AND** the key must NOT have withdrawal permissions (for safety)
- **AND** IP restriction is recommended but optional
