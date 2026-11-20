# Okanzo

Offline-first personal net-worth tracker for organizing assets and liabilities across named portfolios in a chosen base currency.

## Language

### Portfolio & Holdings

**Portfolio**:
A named collection of holdings whose net worth is tracked together. Exactly one portfolio is designated as the **Default Portfolio** opened at startup.
_Avoid_: Account, wallet, workspace

**Holding**:
Any individual **Asset** or **Liability** recorded inside a portfolio.
_Avoid_: Item, position, entry

**Asset**:
A holding with positive economic value owned in a portfolio, categorized by asset type (such as stock, mutual fund, crypto, metals, cash, bank deposit, real estate, vehicle, bond, or other).

**Liability**:
A debt or financial obligation owed inside a portfolio (such as a loan, mortgage, credit card, pending payment, tax, or other) subtracted from total assets to compute net worth.

**Net Worth**:
A portfolio's point-in-time total assets minus total liabilities, converted into the **Base Currency**.

### Valuation & Currency

**Valuation Mode**:
The rule that determines an asset's value in its native currency: **Market** (units multiplied by the latest quote), **Metal** (grams multiplied by a purity-adjusted rate), **Quantity** (units multiplied by a manual unit price), or **Flat** (a single manual total value).

**Metal Purity**:
The share of a holding's weight made of the named metal. Gold purity is expressed in karats; Silver, Platinum, and Palladium use fineness in parts per thousand.
_Avoid_: Carat (a unit of gemstone weight)

**Base Currency**:
The display currency into which all holdings and totals are converted using USD-pivoted foreign exchange rates.
_Avoid_: Home currency, primary currency

### Privacy & Security

**Hide Balances**:
A persisted shoulder-surfing privacy mode across read-only browsing surfaces that masks every monetary figure and holding quantity, while keeping portfolio structure, names, tickers, holding counts, and relative percentage allocations visible.
_Avoid_: Incognito mode, stealth mode
