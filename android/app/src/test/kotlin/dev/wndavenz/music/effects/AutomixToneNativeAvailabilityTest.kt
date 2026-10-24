package dev.wndavenz.music.effects

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomixToneNativeAvailabilityTest {
    @Test
    fun libraryAvailabilityIsRequiredBeforeCallingToneSymbols() {
        val availability = AutomixToneNativeAvailability()

        assertFalse(availability.canUse(libraryAvailable = false))
        assertTrue(availability.canUse(libraryAvailable = true))
    }

    @Test
    fun linkageFailureDisablesLaterToneCallsForTheProcess() {
        val availability = AutomixToneNativeAvailability()

        availability.markUnavailable()

        assertFalse(availability.canUse(libraryAvailable = true))
        assertFalse(availability.canUse(libraryAvailable = true))
    }
}
