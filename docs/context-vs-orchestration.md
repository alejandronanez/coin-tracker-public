# Context vs Process Orchestration

## The Key Distinction

**Contexts handle business logic. Workers/GenServers handle infrastructure orchestration.**

This is a fundamental separation of concerns in Phoenix applications that keeps code maintainable and testable.

## What Contexts SHOULD Handle (Business Logic)

Contexts are responsible for **domain rules** - the "what" and "why" of your application:

- **Domain rules**: "Can't delete a symbol_price if positions reference it"
- **Validation**: "Price must be positive", "Exchange must be valid"
- **Transactions**: "When creating a position, also update user's balance"
- **Calculations**: "Calculate average price across exchanges"
- **Complex queries**: "Find all stale prices that need refreshing"
- **Authorization**: "User can only see their own positions"

**Example:**
```elixir
defmodule CoinTracker.Coins do
  def upsert_symbol_price(attrs) do
    %SymbolPrice{}
    |> SymbolPrice.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:exchange, :symbol_pair]
    )
  end
end
```

This is pure business logic: validate data, persist it. No retries, no scheduling, no alerts.

## What Contexts SHOULD NOT Handle (Infrastructure Concerns)

Infrastructure concerns are about **how the system operates** - the "when" and "how":

- **Retries**: Process-level orchestration (GenServer/supervisor)
- **Scheduling**: "Poll every 30 seconds" (GenServer + timer)
- **Alerting**: Sending emails/Slack messages (separate service)
- **Long-running work**: Background jobs (Oban, Task.Supervisor)
- **Circuit breakers**: Handling external service failures
- **Rate limiting**: Throttling API calls

**Example:**
```elixir
defmodule CoinTracker.PricePoller do
  use GenServer

  def handle_info(:poll, state) do
    case fetch_prices_from_api() do
      {:ok, prices} ->
        Enum.each(prices, fn price ->
          # Call the context (business logic)
          case Coins.upsert_symbol_price(price) do
            {:ok, _} -> :ok
            {:error, changeset} ->
              # Orchestration logic: retry, alert, etc.
              handle_failure(changeset, state.retry_count)
          end
        end)

      {:error, _reason} ->
        # Infrastructure concern: circuit breaker, backoff, etc.
        schedule_retry()
    end

    {:noreply, state}
  end

  defp handle_failure(changeset, retry_count) when retry_count > 3 do
    # Alert admin (infrastructure concern)
    AdminNotifier.send_alert("Price update failing", changeset)
  end
end
```

## The Pattern in Phoenix

```
LiveView/Controller (UI Layer)
    ↓
Context (Business Logic Layer)
    ↓
Schema/Repo (Data Layer)

GenServer/Worker (Infrastructure Layer)
    ↓
Context (Business Logic Layer)
    ↓
Schema/Repo (Data Layer)
```

Notice how both the UI layer and the infrastructure layer call into the Context. The Context is the **stable interface** to your business logic.

## Why This Separation Matters

### 1. Testability
- Context tests are simple: "given this input, does it validate/persist correctly?"
- You don't need to mock timers, retries, or external services

### 2. Reusability
- The same context function can be called from:
  - LiveViews (user manually updating price)
  - GenServers (automated polling)
  - IEx console (admin operations)
  - Tests

### 3. Clarity
- Context functions have clear, focused responsibilities
- Infrastructure concerns don't leak into business logic
- Changes to retry logic don't require touching domain code

## Real-World Example: Price Updates

**Wrong approach (mixing concerns):**
```elixir
defmodule CoinTracker.Coins do
  def upsert_symbol_price(attrs) do
    # Business logic mixed with infrastructure
    changeset = SymbolPrice.changeset(%SymbolPrice{}, attrs)

    case Repo.insert(changeset, on_conflict: :replace_all) do
      {:ok, price} ->
        {:ok, price}
      {:error, changeset} ->
        # Infrastructure concern in context!
        if retry_count < 3 do
          Process.sleep(1000)
          upsert_symbol_price(attrs, retry_count + 1)
        else
          AdminNotifier.alert("Failed to update price")
          {:error, changeset}
        end
    end
  end
end
```

**Right approach (separation):**
```elixir
# Context: Simple business logic
defmodule CoinTracker.Coins do
  def upsert_symbol_price(attrs) do
    %SymbolPrice{}
    |> SymbolPrice.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:exchange, :symbol_pair]
    )
  end
end

# Worker: Infrastructure orchestration
defmodule CoinTracker.PricePoller do
  use GenServer

  def handle_info(:poll, state) do
    prices = fetch_from_api()

    Enum.each(prices, fn price_attrs ->
      # Orchestration: retry logic
      case retry_with_backoff(fn ->
        Coins.upsert_symbol_price(price_attrs)
      end) do
        {:ok, _} -> :ok
        {:error, _} -> AdminNotifier.alert("Price update failed")
      end
    end)

    schedule_next_poll()
    {:noreply, state}
  end
end
```

## Summary

- **Contexts** = Business rules about your domain (cryptocurrency tracking)
- **Workers/GenServers** = Infrastructure rules about system operation (polling, retrying, alerting)
- Keep them separate for testability, reusability, and clarity
- The context should be callable from anywhere without side effects
