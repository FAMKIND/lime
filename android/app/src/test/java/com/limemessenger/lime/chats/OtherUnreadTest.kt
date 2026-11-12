package com.limemessenger.lime.chats

import org.junit.Assert.assertEquals
import org.junit.Test

/** LIME-409: the number beside a chat's Back is the Messages tab's unread-chat count minus this chat (iOS LIME-325's rule). */
class OtherUnreadTest {
    private fun list(vararg unread: Boolean) = unread.mapIndexed { i, u -> "c$i" to u }

    @Test fun thisChatIsNotCountedWhenItIsUnread() {
        val chats = list(true, true, true)   // three unread chats, the open one among them
        assertEquals("the tab says 3; inside c0 the others are 2", 2, countOtherUnread(chats, "c0"))
    }

    @Test fun anUnreadChatIsCountedFromAReadOne() {
        assertEquals(2, countOtherUnread(list(false, true, true), "c0"))
    }

    @Test fun noneUnreadMeansZeroAndNoNumber() {
        assertEquals(0, countOtherUnread(list(false, false), "c1"))
        assertEquals(0, countOtherUnread(emptyList(), "c1"))
        assertEquals("the open chat alone unread", 0, countOtherUnread(list(true), "c0"))
    }

    @Test fun chatsNotMessagesAndMutedAsTheTab() {
        // The tab counts chats (one per chat whatever its messages) and does not leave muted chats out; so neither does the Back.
        assertEquals(120, countOtherUnread((0 until 121).map { "c$it" to true }, "c0"))
    }
}
