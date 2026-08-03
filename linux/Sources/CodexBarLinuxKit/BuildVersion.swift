/// The version this binary reports.
///
/// Rewritten by `linux/packaging/set-version.sh` during a release build; the
/// committed value is what a plain checkout build reports, and it deliberately
/// carries a `-dev` suffix so a development binary can never be mistaken for a
/// released one.
public enum BuildVersion {
    public static let marketing = "0.0.0-dev"
}
