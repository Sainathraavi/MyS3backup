# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

# User specific aliases and functions

prompt() {
#    PS1="\[\e[32m\]\u\[\e[m\]\[\e[32m\]@\[\e[m\]\[\e[32m\]\h\[\e[m\]\[\e[30m\]($ENVIRONMENT)($NAME)$\[\e[m\]\[\e[37m\] "
PS1="\[\033[38;5;4m\]\u\[$(tput sgr0)\]\[\033[38;5;2m\]@\[$(tput sgr0)\]\[\033[38;5;4m\]\h\[$(tput sgr0)\]\[\033[38;5;2m\]:\[$(tput sgr0)\]\[\033[38;5;4m\]\w\[$(tput sgr0)\]\[\033[38;5;7m\]($ENVIRONMENT)($NAME)\[$(tput sgr0)\]\[\033[38;5;15m\]\\$\[$(tput sgr0)\] "
}

PROMPT_COMMAND=prompt


export ECR=551255458270.dkr.ecr.us-east-1.amazonaws.com
export ECR2=551255458270.dkr.ecr.us-west-2.amazonaws.com
alias ecr-login='`aws ecr get-login --region us-east-1` && `aws ecr get-login --region us-west-2`'
alias docker-rme='docker rm -v $(docker ps -a -q -f status=exited)'
alias docker-rmi='docker rmi $(docker images -f "dangling=true" -q)'
