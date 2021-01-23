function! notmuch#CompTags(ArgLead, CmdLine, CursorPos)
	let l:c = v:lua.require('notmuch.comp')
	return l:c.complete(a:ArgLead, a:CmdLine, a:CursorPos)
endfunction
