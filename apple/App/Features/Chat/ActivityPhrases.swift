// SPDX-License-Identifier: AGPL-3.0-or-later
// Localized phrase pools from DSH Go app/lib/ui/chat/activity_copy.dart.
import Foundation

extension ActivityCopy {
    typealias Pool = [String.LocalizationValue]

    static let thinking: Pool = [
        "Hmm… let me untangle this",
        "Let’s work through this",
        "Brain gears turning",
        "Give me a second",
        "Brain’s working overtime",
        "Thinking, thinking",
        "One thought at a time",
        "Let me ponder that",
        "Working through the logic",
        "Putting my brain to work",
        "Let me sort this out",
        "Searching my memory",
        "Brainstorming",
        "Hmm… let that sink in",
        "One moment, thinking",
        "Scratching my head…",
        "Let’s see where this goes",
        "Thoughts loading",
        "Mulling it over",
        "Hmm… let me break it down",
        "All aboard the thought train",
        "Hmm… there’s something here",
        "Taking this idea for a jog",
        "Wait, I can picture it",
        "Thought bubbles",
        "Brainwaves incoming",
        "Brain’s brewing coffee",
        "Drafting it in my head",
        "Ah, it’s coming to me",
        "Ideas bubbling up",
        "Hmm… let’s tackle it",
        "A spark of an idea",
        "Let’s sort the logic first",
        "Pinpointing it",
        "Looking into it",
        "thinking.gif",
        "Lemme take a look",
        "Hmm… interesting",
        "Warming up my brain",
        "loading 99%"
    ]
    static let waiting: Pool = [
        "Calling the model…",
        "Model’s on its way",
        "Waiting for a word…",
        "Finding the right words",
        "Is the model awake yet?",
        "Letting it stretch",
        "The model just yawned",
        "Model: on my way",
        "Waiting for the first words",
        "Still in the queue",
        "Something’s brewing",
        "Model’s taking a sip",
        "Letting it warm up",
        "Model’s meditating",
        "Waiting for it to blink",
        "It says, “one moment”"
    ]
    static let writing: Pool = [
        "Finding the words",
        "Typing away",
        "Words flowing like magic",
        "Writing, writing",
        "Choosing each word",
        "All in one flow",
        "Putting it in plain words",
        "Putting ideas into words",
        "Tapping away",
        "Almost done writing",
        "Let me tell you",
        "Writing up a storm",
        "Words flying onto the page",
        "Tidying up the layout"
    ]
    static let night: Pool = [
        "Transcending bedtime…",
        "A little late-night hello",
        "You’re a night owl too?",
        "If the moon’s up, I’m up",
        "Late-night brain, go easy",
        "Night owl champion online",
        "Sleepy, but I’ve got this",
        "Still going past midnight",
        "Open for the night shift",
        "Even the stars are asleep",
        "Thinking into the small hours"
    ]
    static let weekend: Pool = [
        "A little weekend chill",
        "Here on weekends too!",
        "Here on days off too",
        "No weekend shutdown",
        "Sneaky weekend thinking",
        "Working on the weekend too?",
        "Weekend mode ON",
        "Weekend bug fixing",
        "Weekend-exclusive look"
    ]
    static let rare: Pool = [
        "SSR! Rare Easter egg",
        "UR drop",
        "Legendary drop!",
        "An orange-tier drop",
        "An Easter egg found you",
        "The chosen moment",
        "You found the hidden edition",
        "Secret chat unlocked",
        "Rarity MAX",
        "Luck is on your side",
        "Critical hit",
        "Next-level thinking"
    ]
    static let fail: Pool = [
        "Well, that went sideways",
        "Oops",
        "That didn’t run",
        "A little stumble",
        "That’s not right",
        "Hit a hiccup",
        "That’s not working",
        "It works on my machine",
        "It worked yesterday",
        "That’s a tough one",
        "Well, that fell apart",
        "Feeling the pressure",
        "Got a little careless there",
        "A slip of the keys",
        "Let’s try another way",
        "Give me another shot"
    ]
    static let testPass: Pool = [
        "All tests green",
        "All green. Nice",
        "Passed first try!",
        "No errors",
        "It passed!",
        "Looking solid"
    ]
    static let testFail: Pool = [
        "Red. Let’s see what broke",
        "Tests failed. Looking into it",
        "One stubborn test",
        "Red light. Back to fixing"
    ]
    static let gitCommit: Pool = [
        "Committed. Progress saved",
        "Progress saved",
        "Committed. Peace of mind"
    ]
    static let gitPush: Pool = [
        "Pushed",
        "Pushed. Off it goes",
        "Code’s out the door"
    ]
    static let install: Pool = [
        "Dependencies installed",
        "Downloaded half the internet",
        "All packages present"
    ]
    static let retry: Pool = [
        "Hang tight, retrying",
        "Turned away. Backing off",
        "Knocking once more"
    ]
    static let rateLimit: Pool = [
        "Rate limited. Taking a break",
        "429. A breather, then retry",
        "Quite a queue today"
    ]
    static let compaction: Pool = [
        "Tidying up the context…",
        "Organizing my backpack…",
        "Making some room",
        "Trimming my memory",
        "Packing up old chats"
    ]
    static let longThinking: Pool = [
        "Five minutes. Quite a project",
        "Time to get serious",
        "This is a bit tricky",
        "Reaching a higher plane",
        "Almost there, promise",
        "Took the scenic route",
        "Wrapping things up",
        "Give me one song’s worth",
        "Preparing the big move",
        "Easy request. Or is it?"
    ]
    static let deepThinking: Pool = [
        "One minute, still thinking",
        "Now that’s a challenge",
        "Let me dig a little deeper",
        "There’s more to this",
        "Getting deep into it",
        "Brain cells firing away",
        "Almost figured it out",
        "This one’s a little twisty…",
        "Giving my brain a workout…",
        "Stay with me, almost there"
    ]
    static let moreThinking: Pool = [
        "Let me think this through",
        "Thirty seconds, still at it",
        "Hang tight, nearly there",
        "Let me take another pass",
        "Still on track",
        "Getting somewhere",
        "Going in circles…",
        "Any moment now",
        "Still narrowing it down"
    ]
    static let holidays: [Int: Pool] = [
        101: ["Happy New Year!", "Happy New Year", "New year, new bugs", "First line of code this year", "Here’s to a great start"],
        214: ["Coding on Valentine’s Day too", "Code is true love", "No date today?", "Keyboards are my roses"],
        314: ["Happy π Day", "3.1415926…", "Extra-round circles today"],
        401: ["Happy April Fools’ Day", "This bug’s a prank, right?", "Watch out for prank errors", "Just kidding, no errors"],
        501: ["Still working on Labor Day", "A little pride in the work", "Worker mode: all in"],
        601: ["Happy Children’s Day", "We’re all kids at heart", "Cute code only today"],
        1024: ["Happy 1024 Programmers’ Day", "It’s Programmers’ Day", "1024, happy coding day", "Coding on our holiday too"],
        1031: ["Happy Halloween", "Trick or treat", "Code can be spooky too"],
        1224: ["Happy Christmas Eve", "Thinking on Christmas Eve too", "Code tonight, gifts await"],
        1225: ["Merry Christmas", "Here with you for Christmas", "A Christmas-only Easter egg", "Reindeer delivering code"],
        1231: ["New Year’s Eve", "One last thought this year", "Ready for the new year", "See you next year!"],
    ]
    static let lunar: Pool = [
        "Happy Lunar New Year!",
        "Still coding over New Year",
        "Red envelopes, please",
        "Happy Spring Festival",
        "New Year greetings",
        "The code says Happy New Year"
    ]
    static let zodiac: Pool = [
        "Rat",
        "Ox",
        "Tiger",
        "Rabbit",
        "Dragon",
        "Snake",
        "Horse",
        "Goat",
        "Monkey",
        "Rooster",
        "Dog",
        "Pig"
    ]
    static let milestones: [Int: String.LocalizationValue] = [
        5: "Tools x5, getting into it",
        10: "Tool combo x10",
        20: "Tools x20, on a roll",
        50: "Tools x50, working overtime",
    ]
}
