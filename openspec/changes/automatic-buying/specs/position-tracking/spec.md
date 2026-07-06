## MODIFIED Requirements

### Requirement: Position source field

The position schema SHALL include a `source` field that indicates how the position was created.

#### Scenario: Manual position creation
- **WHEN** a user creates a position via `/positions/new`
- **THEN** the position's `source` is set to `"manual"`

#### Scenario: Auto-buy position creation
- **WHEN** a position is created by `Trading.AutoBuy.execute/4`
- **THEN** the position's `source` is set to `"auto_buy"`

#### Scenario: Existing positions default to manual
- **WHEN** the `source` migration runs
- **THEN** all existing positions have `source` set to `"manual"`

### Requirement: Source badge on position list

The `/positions` page SHALL visually distinguish auto-created positions from manual ones.

#### Scenario: Auto-buy position displays badge
- **WHEN** the position list renders a position with `source: "auto_buy"`
- **THEN** a small badge or indicator is shown (e.g., "Auto" label)
- **AND** the badge does not interfere with the existing PnL and alert display

#### Scenario: Manual position displays no badge
- **WHEN** the position list renders a position with `source: "manual"`
- **THEN** no source badge is shown (to avoid visual noise on existing positions)
