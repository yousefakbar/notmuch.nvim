setlocal conceallevel=3
setlocal concealcursor=n

syntax region nmThreads		start=/^/ end=/$/					oneline contains=nmThreadNum
syntax match nmThreadNum	"^thread"						contained nextgroup=nmThreadEllipsis conceal
syntax match nmThreadEllipsis	":"							contained nextgroup=nmThreadID conceal
syntax match nmThreadID		"[0-9a-z]\+"						contained nextgroup=nmDate conceal
syntax match nmDate		"\s\+[0-9A-Za-z.\-]\+\(\s[a-z0-9:.]\+\)\?\(\sago\)\?"	contained nextgroup=nmThreadCount
syntax match nmThreadCount	"\s\+\[[0-9]\+\/[0-9()]\+\]"				contained nextgroup=nmFrom
syntax match nmFrom		"\s\+.*;"						contained nextgroup=nmSubject
syntax match nmSubject		/.\{0,}\(([^()]\+)$\)\@=/				contained nextgroup=nmTags
syntax match nmTags		"(.*)$"							contained

highlight link nmThreadNum	Type
highlight link nmThreadEllipsis	Normal
highlight link nmThreadID	Include
highlight link nmDate		String
highlight link nmThreadCount	Comment
highlight nmFrom		ctermfg=224 guifg=Orange gui=italic
highlight link nmSubject	Statement
highlight link nmTags		Comment
