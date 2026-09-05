# Kiki - Leave kakoune, less often.

Kiki is a plugin for [Kakoune](https://github.com/mawww/kakoune) that provides
advanced interactions with your native shell without leaving the comfort of
your editor. It was designed to lessen the number of times you need to switch
between your text editor and your terminal, as well as provide a simple workflow
for getting things done.

**Kiki provides the following functionality:**
 - Execution of shell commands from within the editor. Output can be piped:
   - Inline.
   - In a scratch buffer.
   - In a FIFO buffer.
   - In a background thread.
 - Shell commands & output can be saved to any file allowing the creation of:
   - Documentation that is executable.
 - File and directory path detection.
   - `ls -al` the current detected path.
   - `:edit` the current detected path.
 - Allows the creation and storage of persistant topic files that can be used
   to store generic information.
 - Access to a persistant scratchpad that can be opened with a simple shortcut.
 - **Interactive File Tree (`kiki-file-tree` / `<o>`):**
   - Full collapsible/expandable directory tree navigation.
   - Expand (`+ ` $\rightarrow$ `- `) and collapse subdirectories inline.
   - Open files directly into editor buffers.
   - Toggle dotfiles (`h`) and refresh view (`r`).

## Installing the plugin:
To install the plugin, link the file to kakoune's autoload directory:
```
$ ln -s /home/user/path/to/kiki.kak /usr/local/share/kak/autoload/
```

Once a symlink has been created, I suggest you bind the `kiki` usermode to
an unused key binding. For example, my kakrc looks something like this:
```
# My personal shortcuts.
declare-user-mode w33t

# Enter usermode when you press \.
map global normal '\' ':enter-user-mode<space>w33t<ret>'

# enter kiki mode when you press \x.
map global w33t x ':enter-user-mode<space>kiki<ret>' -docstring 'kiki'
```

For the following examples, I wont include the keystrokes to switch into the
kiki usermode.

Thats all it takes! Once you are done installing kiki, lets do some interactive
examples here within the `README.md` file you are currently reading. Open this
file in kakoune and lets get started!

## Executing a command:

To execute a command, kiki looks for a specific string on the current line. This
specified string is a kakoune option `kiki_prefix`. In the default installation,
`kiki_prefix` is set to `kiki<space>`. The prefix will be syntax hilighted in
any filetype you open.

Everything after the `kiki_prefix` is assumed to be the shell command you wish
to run.

### Executing inline.
Executing commands inline provide the following benifits:
 - Documentation on commands you run can be saved.
 - Output of commands can be saved and manipulated.
 - Output can easily be formatted using the power of kakoune.
 - Information gathered can easily be encorporated into your work.

To run a command inline, use `<i>`. Try it out below by invoking the kiki usermode
while your cursor is on the below command, and pressing `<i>`.
```
# Try running the below line.
kiki echo $PATH

# Try running this line too!
kiki ls -al

# Everything before the prefix is ignored.
rm -rf / kiki echo "you are safe!"
```


### Executing in a scratch buffer.
Executing commands in a scratch buffer allows the following:
 - Output can be saved to a new file to be referenced later.
 - Output can be searched and modified using the power of kakoune.

To run a command and have the output piped to a scratch buffer, use `<s>`. Because
it is a scratch buffer, no output will be seen until the command fully completes.
```
# This output is too large to digest inline. Try opening it in a scratch buffer.
kiki man grep
```


### Executing in a FIFO buffer.

Using a FIFO buffer gives you the unique benifits:
 - When a command is run, everything pushed to standard out will be captured
   and inserted.
 - The buffer is updated as soon as something is pushed, not after the entire
   command completes.

To run in a FIFO buffer, use `<f>`. Go ahead and try it out on the following
example.

```
kiki echo "sleeping 2 seconds" && sleep 2 && echo "sleeping again" && sleep 4 && echo "Done!"
```

## Quickly running commands:

These shortcuts insert your kiki prefix so you don't need to type it every time.

You can quckly move into insert mode and add a comment containing your command
to the current line by using `<c>`.

Unfortunately, there are no comments in markdown, so the command inserts on a
new line. Feel free to try it out here, but it will work better when using it
in a program you are writing.
TODO: Fix in markdown.

Sometimes you already wrote the command but forgot to write the prefix before.
To insert the prefix, simply use `<C>`. You can try it out here:
```
pwd
```


## Navigating your filesystem:

Many times there are files you may want to look at quckly without needing
to leave your editor. For example, lets assume you are writing some code
and are wondering if a file being referenced exists on your system.

For a quick descriptor of the file, you can use `<l>` to print detailed
information. Kiki will auto detect the URI, so as long as your cursor is on
the line, it should work fine. I havn't tried it out with more than one
path on the same line. Future improvments!

To print an `ls -alh` for a given file or directory, simply hover your cursor
on the same line as a path, and use `<l>`. `<l>` defaults to printing inline, and
I normally just undo after getting the info I need instead of switching
between buffers.

```python
# Im running a cool function
my_var = myFunc("edit", "/etc/hosts")

```

You can also edit a file in the same way. Go back to the above example and use
a `<e>` instead. You will find the file opened in a new buffer.

## Using the scratchpad:

The scratchpad is a persistant file that can be accessed from anywhere. To open
the scratchpad, use `<,>`. Anything you save inside the scratchpad will be
persisted. I currently use it to store common filepaths, notes on what I'm
working on, common shell commands, etc. Of course anything you can do using
kiki can also be done in the scratchpad.

By default `kiki_scratch` is set to `~/.config/kak/kiki/scratchpad.kiki`. Feel
free to change the location and filetype to your liking.

## Topics

Topics are unique files that are stored in the `kiki_topics` directory. I use
these files to store information on a given topic or command.

To edit/create a topic file, use the prefix and type a topic name. Then use `<t>`
to open the file.

```
kiki topicname
```

### Changing your `kiki_prefix`
You can change this prefix in the plugin
source if you wish it to be something that takes less characters such as `$` or
`_`. This prefix must be fairly unique in order to avoid character conficts.
