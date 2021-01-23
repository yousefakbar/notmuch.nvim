syntax region nmThreads		start=/^/ end=/$/	oneline contains=nmThreadNum
syntax match nmThreadNum	"^thread"	contained nextgroup=nmThreadEllipsis
syntax match nmThreadEllipsis	":"		contained nextgroup=nmThreadID
syntax match nmThreadID		"[0-9a-z]\+"	contained nextgroup=nmDate
syntax match nmDate		"\s\+[0-9A-Za-z.\-]\+\(\s[a-z0-9:.]\+\)\?\(\sago\)\?"	contained nextgroup=nmThreadCount
syntax match nmThreadCount	"\s\+\[[0-9]\+\/[0-9()]\+\]"	contained nextgroup=nmFrom
syntax match nmFrom		"\s\+.*;"			contained nextgroup=nmSubject
syntax match nmSubject	/.\{0,}\(([^()]\+)$\)\@=/	contained nextgroup=nmTags
syntax match nmTags		"(.*)$"			contained

highlight link nmThreadNum	Type
highlight link nmThreadEllipsis	Normal
highlight link nmThreadID	Include
highlight link nmDate		String
highlight link nmThreadCount	Comment
highlight link nmFrom		Special
highlight link nmSubject	Statement
highlight link nmTags		Comment
