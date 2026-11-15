package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.IncomingCallNotifier
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** LIME-427 screenshots: posts the incoming-call notification and leaves it (only with `-e post 1`; `tools/shots-427.sh` photographs the heads-up and the shade). */
@RunWith(AndroidJUnit4::class)
class CallNotificationPoster {
    @Test fun post() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("post") == "1")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        if (args.getString("cancel") == "1") { IncomingCallNotifier.cancel(context); return }
        IncomingCallNotifier.post(context, "shot", (args.getString("name") ?: "Ben_Test").replace("_", " "), args.getString("video") == "1")
    }
}
