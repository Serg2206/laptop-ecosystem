# Экосистема моего ноутбука — MS 365 Workspace

> Полная интеграция рабочего окружения: MS 365, Obsidian, Notion, GitHub, PowerShell автоматизация

## Архитектура экосистемы

```
┌──────────────────────────────────────────────────────────────┐
│                     ЭКОСИСТЕМА НОУТБУКА                       │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│   OBSIDIAN (локальные заметки)                                │
│   ├── Vault в OneDrive\Obsidian\                               │
│   ├── Daily Notes — авто в 7:00                               │
│   └── Git backup → GitHub ежедневно в 18:00                   │
│        ↕                                                       │
│   NOTION (команда + проекты)                                  │
│   ├── Research Projects DB                                    │
│   ├── Integration Tasks DB (10 задач)                         │
│   └── Sync: Obsidian #publish → Notion pages                  │
│        ↕                                                       │
│   GITHUB — github.com/Serg2206/laptop-ecosystem               │
│   ├── PowerShell скрипты (3,247 строк)                        │
│   ├── Веб-витрина (React + 5 страниц)                         │
│   └── Obsidian Vault backup                                   │
│        ↕                                                       │
│   MS 365 TOOLKIT — 5 модулей                                  │
│   ├── OneDrive Launcher — запуск + автозагрузка               │
│   ├── VBA Macros — 14 макросов, автоимпорт                    │
│   ├── Junction Links — OneDrive ↔ Workspace                   │
│   ├── Academic Templates — CRediT/Funding/COI                 │
│   └── Daily Notes — авто + шаблоны + sync                     │
│        ↕                                                       │
│   ДИЗАЙН-СИСТЕМА                                              │
│   ├── 9 шрифтов (Montserrat, Inter, Merriweather...)          │
│   ├── Word: Academic-Modern.dotx                              │
│   └── PowerPoint: Conference-Pro.potx                         │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

## Компоненты

### MS 365 Toolkit (28 файлов)
- **OneDrive Launcher** — `Start-OneDrive.ps1`, `Register-OneDriveAutostart.ps1`
- **VBA Macros** — 4 модуля (.bas): AutoFormat, ExportTools, AcademicTools, TemplateManager
- **Junction Links** — `New-WorkspaceJunctions.ps1` + конфигурация
- **Academic Templates** — CRediT, Funding, COI (.md + .docx)
- **Daily Notes** — `New-DailyNote.ps1` + шаблоны + Task Scheduler

### Дизайн-система
- 9 шрифтов: Montserrat, Inter, Merriweather, Crimson Text, Literata, Source Sans 3, Source Code Pro, Playfair Display, Lora
- Word: `Academic-Modern.dotx` — 10 стилей
- PowerPoint: `Conference-Pro.potx` — 8 типов слайдов

### PowerShell Скрипты (3,247 строк)
| Скрипт | Строк | Назначение |
|--------|-------|------------|
| `Get-WorkspaceStatus.ps1` | 1,007 | Дашборд: OneDrive, Obsidian, Notion API, GitHub, Junctions, Task Scheduler |
| `New-CommandCenter.ps1` | 619 | Интерактивное меню управления экосистемой |
| `Sync-ObsidianToNotion.ps1` | 569 | Markdown→Notion blocks, #publish теги, state management |
| `Backup-ToGitHub.ps1` | 375 | Auto-init git, daily commits, push |

### Веб-витрина
- **Live:** https://iusigf6hsqxqy.kimi.page
- 5 страниц: Home, Templates, Fonts, Dashboard, Workflow
- React 19 + TypeScript + Tailwind CSS + Framer Motion

### Notion
- Research Projects DB — проекты, статьи, гранты
- Integration Tasks DB — 10 задач со статусами

## Быстрый старт

```powershell
# Установить шрифты + шаблоны (администратор)
.\ms365-design\install\Install-Fonts.ps1
.\ms365-design\install\Install-Templates.ps1

# Запустить Command Center — управление экосистемой
.\scripts\New-CommandCenter.ps1
```

## Ссылки
- **GitHub:** https://github.com/Serg2206/laptop-ecosystem
- **Веб-дашборд:** https://iusigf6hsqxqy.kimi.page
- **Notion:** https://app.notion.com
