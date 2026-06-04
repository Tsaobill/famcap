# FamilyWealthApp

A local-first iOS wealth tracker scaffold with family member ownership and nearby device sync.

## Implemented in this scaffold

- SwiftUI app structure with 3 tabs: `Overview`, `Members`, `Assets`
- SwiftData models:
  - `Household`
  - `Member`
  - `Asset`
- Asset ownership by family member (`Asset.owner`)
- Refined asset types (cash/deposit/balance/wealth management/stock/crypto/etc.)
- Valuation modes:
  - `Standard` assets: ticker + quantity, auto price/value
  - `Custom` assets: manual currency + value
- Stock & crypto tracking fields:
  - `symbol`
  - `market` (`US/HK/Global`)
  - `quantity`
  - `autoSyncPrice`
- Asset management UX:
  - Create + edit assets
  - Search and filter
  - Per-asset household/member percentage in list
  - Asset tags: `Asset Category` and `Account/Platform`
- Market data services:
  - `YahooFinanceProvider` for quotes and FX rates
  - `MarketDataCoordinator` for sync and base-currency conversion
- Base currency summary in `Overview` with FX conversion
- Overview charts:
  - Allocation pie chart
  - Net worth trend line (snapshot based)
- Nearby sync services (no iCloud):
  - `NearbySyncService` (`MultipeerConnectivity`)
  - `HouseholdSyncCodec` for payload export/import
- Sample seed data on first launch

## Run

1. Open `/Users/bytedance/capview/FamilyWealthApp/FamilyWealthApp.xcodeproj` in Xcode.
2. Set your own bundle identifier.
3. Select your signing team in `Signing & Capabilities`.
4. Run on an iOS simulator or device.

## Notes

- Nearby sync requires local network permission on first use.
- Current sync mode is snapshot transfer + merge import.
- Market API integration uses Yahoo quote endpoints and should be treated as best-effort for prototype usage.
