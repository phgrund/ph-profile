"""Templates de arquivos e prompts dos agentes."""

TASK_TEMPLATE = """# Tarefa

Descreva a tarefa aqui.

# Link ClickUp

{url}

# Contexto

-

# Critérios de aceite

-

# Restrições

- Backend only.
- Não fazer refactor amplo fora do escopo.
- Manter padrão atual do projeto.
- Adicionar/ajustar testes quando fizer sentido.

# Comandos de validação esperados

- aiw validate
- aiw sail artisan test
"""

PLAN_PROMPT = """Você está em uma worktree isolada para uma tarefa backend Laravel.

Leia:
- .ai/task.md
- .ai/meta.env se existir
- arquivos relevantes do projeto

Objetivo:
- Entender a tarefa
- Fazer perguntas se houver ambiguidade importante
- Propor um plano técnico objetivo
- Não editar arquivos ainda

Ao final, salve o plano aprovado em:

.ai/plan.md

O plano deve conter:
- resumo da tarefa
- arquivos prováveis
- alterações backend
- testes necessários
- riscos
- comandos de validação (esta worktree tem stack sail próprio: use 'aiw sail <cmd>' ou 'aiw validate', não './vendor/bin/sail' de outro terminal)
"""

IMPLEMENT_PROMPT = """Implemente a tarefa conforme:

- .ai/task.md
- .ai/plan.md
- .ai/meta.env se existir

Regras:
- Backend only.
- Não fazer refactor amplo fora do escopo.
- Fazer alterações pequenas e coerentes.
- Criar/ajustar testes quando fizer sentido.
- Para rodar artisan/testes use 'aiw sail <cmd>' (stack próprio desta worktree; se não estiver de pé, peça para rodar 'aiw up').
- Ao terminar, salve um resumo em .ai/implementation-notes.md.
- Não commitar.
"""

FIX_PROMPT = """Leia:

- .ai/task.md
- .ai/plan.md
- .ai/codex-review.md
- diff atual do Git

Aplique somente correções relevantes da revisão.

Regras:
- Não fazer refactor amplo.
- Se discordar de algum ponto, registre em .ai/final-notes.md.
- Não commitar.
- Para rodar artisan/testes use 'aiw sail <cmd>' (stack próprio desta worktree).
- Ao final, atualize .ai/final-notes.md com:
  - correções aplicadas
  - pontos ignorados e motivo
  - comandos que devem ser rodados
"""

REVIEW_PROMPT = """Você é um code reviewer sênior Laravel.

Contexto:
- Tarefa: .ai/task.md
- Plano: .ai/plan.md
- Metadata: .ai/meta.env
- Diff: .ai/patch.diff

Revise o diff.

Priorize:
- bug real
- regressão
- quebra de regra de negócio
- autorização/autenticação
- validação de input
- query pesada/N+1
- migration perigosa
- testes faltantes
- inconsistência com padrões Laravel do projeto

Não reescreva tudo.
Não sugira refactor amplo fora do escopo.
Liste apenas achados acionáveis.

Formato:

## Resumo

## Achados críticos

## Achados médios

## Achados baixos

## Testes faltantes

## Veredito

Use:
- APPROVE
- REQUEST_CHANGES
"""

USAGE = """aiw - agentes de IA em worktrees Git isoladas (Laravel/Sail)

Uso:
  aiw new <slug> [clickup-url]   cria branch ai/<slug> + worktree irmã com .ai/
  aiw up [--skip-seed] [--fresh] sobe stack sail próprio da worktree (portas livres); no primeiro up
                                 roda migrate --seed (--skip-seed pula os seeders); depois disso só
                                 migra de novo com --fresh (migrate:fresh --seed, recria o banco)
  aiw down                       para o stack da worktree (preserva volumes)
  aiw sail <args...>             roda sail com o ambiente do stack da worktree
  aiw plan                       abre o coder em modo plan (gera .ai/plan.md)
  aiw implement                  coder implementa conforme task + plano
  aiw review                     reviewer revisa o diff (gera .ai/codex-review.md)
  aiw fix                        coder corrige com base na review
                                 (plan/implement/fix aceitam --model <m> e --effort <nível>,
                                 repassados ao coder: claude --model/--effort, codex -m/-c)
  aiw validate                   roda testes/pint/phpstan no stack da worktree (log em .ai/validation.log)
  aiw status                     mostra estado da tarefa
  aiw clean [--prune]            derruba o stack (com volumes) e remove a worktree (com confirmação);
                                 --prune apaga também a branch ai/<slug>

Agentes (defina antes do 'aiw new', ficam gravados em .ai/meta.env):
  AIW_CODER=claude|codex     (default: claude)
  AIW_REVIEWER=codex|claude  (default: codex)

Nota: vendor é clone por hardlinks e .env é cópia do repo base (symlinks
quebrariam dentro do container). AIW_NO_CODE=1 pula abrir o VS Code;
a resposta "sempre"/"nunca" no prompt fica salva em ~/.config/aiw/config.
"""
