#!chezscheme
;;; completion.sls -- Shell completion script generation
;;; Generates bash and zsh completion scripts from CLI app definitions.

(library (std cli completion)
  (export generate-bash-completion generate-zsh-completion)

  (import (chezscheme)
          (std cli multicall))

  ;; --- Bash completion ---

  (define (generate-bash-completion app)
    (let ((name (cli-name app))
          (cmds (cli-commands app)))
      (let ((cmd-names (string-join
                         (append '("help" "version")
                                 (map cli-cmd-name cmds))
                         " ")))
        (string-append
          "_" name "()\n"
          "{\n"
          "    local cur prev commands\n"
          "    COMPREPLY=()\n"
          "    cur=\"${COMP_WORDS[COMP_CWORD]}\"\n"
          "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n"
          "    commands=\"" cmd-names "\"\n"
          "\n"
          "    if [ $COMP_CWORD -eq 1 ]; then\n"
          "        COMPREPLY=( $(compgen -W \"${commands}\" -- ${cur}) )\n"
          "        return 0\n"
          "    fi\n"
          "}\n"
          "complete -F _" name " " name "\n"))))

  ;; --- Zsh completion ---

  (define (generate-zsh-completion app)
    (let ((name (cli-name app))
          (cmds (cli-commands app)))
      (string-append
        "#compdef " name "\n"
        "\n"
        "_" name "() {\n"
        "    local -a commands\n"
        "    commands=(\n"
        "        'help:Show help message'\n"
        "        'version:Show version'\n"
        (apply string-append
               (map (lambda (cmd)
                      (string-append
                        "        '" (cli-cmd-name cmd)
                        ":" (escape-zsh-desc (cli-cmd-description cmd)) "'\n"))
                    cmds))
        "    )\n"
        "\n"
        "    _arguments '1:command:->cmds' '*::arg:->args'\n"
        "\n"
        "    case $state in\n"
        "        cmds)\n"
        "            _describe 'command' commands\n"
        "            ;;\n"
        "    esac\n"
        "}\n"
        "\n"
        "_" name "\n")))

  ;; --- Helpers ---

  (define (escape-zsh-desc str)
    ;; Escape single quotes and colons for zsh completion descriptions
    (let lp ((i 0) (acc '()))
      (if (>= i (string-length str))
        (list->string (reverse acc))
        (let ((c (string-ref str i)))
          (cond
            ((char=? c #\') (lp (+ i 1) (append '(#\' #\\  #\' #\') acc)))
            ((char=? c #\:) (lp (+ i 1) (cons #\- acc)))
            (else (lp (+ i 1) (cons c acc))))))))

  (define (string-join strs sep)
    (if (null? strs)
      ""
      (let lp ((rest (cdr strs)) (acc (car strs)))
        (if (null? rest)
          acc
          (lp (cdr rest) (string-append acc sep (car rest)))))))

  ) ;; end library
