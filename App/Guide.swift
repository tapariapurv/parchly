/// The getting-started document shown on first launch and from Help › Markdown Guide.
enum Guide {
    static let text = """
    # Welcome to Parchly

    Parchly is a calm place to write. Your notes are plain **Markdown** files, so they open anywhere, and Parchly makes them read like a finished page.

    > [!TIP]
    > You don't need to learn any syntax. Use the **formatting bar** at the bottom of the window, or the **Format** menu. Everything has a shortcut.

    ## The basics

    - **Bold** with ⌘B, *italic* with ⌘I, ~~strikethrough~~ with ⇧⌘X
    - Headings with ⌘1 to ⌘6 (⌘0 returns to body text)
    - Select a word and type `*`, `_`, `` ` `` or `==` to wrap it, like ==this==
    - Paste a link over selected text to make a [link](https://github.com/tapariapurv/parchly)

    ## Lists and tasks

    1. Press Return to continue a list
    2. Press Tab to nest an item, Shift-Tab to bring it back
    3. Numbers fix themselves

    - [x] Click a checkbox to tick it
    - [ ] Or press ⌘L

    ## Tables

    | Press | To |
    | --- | --- |
    | ⌥⌘T | Insert a table |
    | Tab | Move to the next cell |
    | Return | Add a row |

    ## Notes that link together

    Type `[[Another Note]]` to link to another note in this folder. ⌘-click the link to open it, and Parchly creates the note if it doesn't exist yet. Jump to a heading with `[[Another Note#Some Heading]]`, or link within this page: [back to the top](#welcome-to-parchly).

    ## Code, math and diagrams

    ```swift
    let greeting = "Hello, Parchly"   // fenced code is colour-coded
    ```

    Inline math like $E = mc^2$ and blocks:

    $$
    \\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}
    $$

    ```mermaid
    graph LR
      Write --> Preview --> Share
    ```

    Open the side-by-side preview (⌘\\\\) to see math and diagrams rendered. Footnotes work too.[^1]

    ## Find anything

    - ⌘P finds any Markdown file in this folder
    - ⇧⌘O jumps to a heading
    - ⌘F finds text, ⌥⌘F replaces
    - Press Space on a `.md` file in Finder for a Quick Look preview

    ## Make it yours

    Open **Settings** (⌘,) to pick a theme, change the text size, or turn on line numbers for Source mode (⌃⌘2). Parchly keeps itself up to date.

    [^1]: Like this one.
    """
}
