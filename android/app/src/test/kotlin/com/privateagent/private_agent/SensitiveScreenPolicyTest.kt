package com.privateagent.private_agent
import org.junit.Assert.*
import org.junit.Test

class SensitiveScreenPolicyTest {
    @Test fun paymentAppsAndSensitiveFieldDesignsAreBlocked() {
        for (p in listOf("com.phonepe.app", "com.google.android.apps.nbu.paisa.user", "org.test.banking.app"))
            assertTrue(p, SensitiveScreenPolicy.protectedPackage(p))
        for (label in listOf("OTP", "enter PIN", "upi_pin", "One-time code", "CVV", "API key", "password"))
            assertTrue(label, SensitiveScreenPolicy.protectedField(false, label))
        assertTrue(SensitiveScreenPolicy.protectedField(true, "unknown field"))
    }
    @Test fun ordinaryAppsAndNonSensitiveTextRemainAvailable() {
        assertFalse(SensitiveScreenPolicy.protectedPackage("org.example.notes"))
        for (label in listOf("shopping list", "spinning animation", "Turn left", "meeting notes"))
            assertFalse(label, SensitiveScreenPolicy.protectedField(false, label))
    }
}
