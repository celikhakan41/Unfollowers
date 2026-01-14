import Foundation
import ObjectiveC

private var kLangBundleKey: UInt8 = 0

extension Bundle {
    private class LocalizedBundle: Bundle, @unchecked Sendable {
        override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
            if let bundle = objc_getAssociatedObject(Bundle.main, &kLangBundleKey) as? Bundle {
                return bundle.localizedString(forKey: key, value: value, table: tableName)
            }
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }

    static func setLanguage(_ language: String) {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            objc_setAssociatedObject(Bundle.main, &kLangBundleKey, langBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            object_setClass(Bundle.main, LocalizedBundle.self)
        } else {
            // Fallback to system/local default by clearing associated bundle
            objc_setAssociatedObject(Bundle.main, &kLangBundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            object_setClass(Bundle.main, LocalizedBundle.self)
        }
    }
}
