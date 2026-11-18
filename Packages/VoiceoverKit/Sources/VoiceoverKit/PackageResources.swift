import Foundation

/// The package's own resource bundle (its string catalog). Inside the test target `Bundle.module` names the
/// tests' bundle instead, so the tests reach the package's translations through this.
enum PackageResources {
    static var bundle: Bundle { .module }
}
