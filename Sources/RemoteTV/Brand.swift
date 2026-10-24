import LGWebOS
import RemoteTVCore

/// The one place the app names a brand. To build for another brand, add a target
/// that implements `TV` and `TVBrand` (see `LGWebOS`) and return it here.
let brand: any TVBrand = LGWebOSBrand()
