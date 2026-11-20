package com.privateagent.private_agent

/** Pure policy; never stores the inspected text. This is a conservative guard,
 * not an exhaustive classifier for all banks, websites or OTP field designs. */
internal object SensitiveScreenPolicy {
    private val packages = setOf(
        "com.google.android.apps.nbu.paisa.user", "net.one97.paytm", "com.phonepe.app",
        "in.org.npci.upiapp", "com.whatsapp.w4b.payment", "com.sbi.lotusintouch",
        "com.csam.icici.bank.imobile", "com.snapwork.hdfc", "com.axis.mobile",
        "com.paypal.android.p2pmobile", "com.android.permissioncontroller",
        "com.google.android.permissioncontroller"
    )
    private val packageWords = Regex("(^|[._])(bank|banking|upi|payment|payments|wallet)([._]|$)", RegexOption.IGNORE_CASE)
    private val sensitiveWords = Regex("(^|[^a-z])(password|passcode|otp|pin|cvv|cvc|upi|one[ _-]?time[ _-]?(password|code)|verification[ _-]?code|card[ _-]?number|api[ _-]?key)([^a-z]|$)", RegexOption.IGNORE_CASE)
    fun protectedPackage(name: String): Boolean = name in packages || packageWords.containsMatchIn(name)
    fun protectedField(password: Boolean, vararg labels: String): Boolean =
        password || labels.any { sensitiveWords.containsMatchIn(it) }
}
