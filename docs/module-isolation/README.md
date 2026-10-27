# Module isolation: design proposal

Epic: [COLDBOX-1478](https://ortussolutions.atlassian.net/browse/COLDBOX-1478)

This is a proposal for discussion. Nothing here is merged, and every part of the design can change.

## The problem

CommandBox installs a module's dependencies inside that module's own `modules` folder, so two modules can each bring a different version of the same dependency:

```
modules/
  bar/modules/qb    13.3.1
  foo/modules/qb    11.1.0
```

ColdBox identifies modules by name only. It loads the first `qb` it finds, skips the other, and gives both `bar` and `foo` the copy it loaded. It logs this at debug level only. A module can end up running a version outside the range it declares in its `box.json`, depending only on load order.

## Goals

- **Opt-in.** With the setting off, ColdBox behaves exactly as it does today.
- **No changes for module authors.** It works with modules as they are published now.
- **No cost on normal lookups.** `getInstance()` does not change.
- **ColdBox never copies or moves a module folder.**

## What ColdBox controls and what it does not

A module is known by three kinds of names:

1. **WireBox IDs**, such as `QueryBuilder@qb`, and module settings.
2. **MVC names**, such as `qb:main.index` and the module's entry point.
3. **Class paths**, such as `qb.models.Query.QueryBuilder`.

ColdBox owns the first two, so it can make them mean a different copy for different modules. The engine owns the third. A class path is resolved through mappings shared by the whole application, and no engine can make `qb` mean a different folder for different callers. This was tested on BoxLang, Lucee 5 and Adobe 2025.

So the design handles injection and MVC names in ColdBox, and handles class paths with a separate rename step for the modules that need it.

## Proposed behaviour

### The setting

```cfml
// config/ColdBox.cfc
modules = {
    isolation : true,            // or "strict": fail at startup if a module cannot be isolated
    shared    : [ "cbdebugger" ] // optional: always keep one copy of these
};
```

### Which copy a module uses

A module uses the closest copy: the one inside its own folder, else its parent's, else the first one loaded. This is the rule CommandBox uses when it installs them: a module sees modules at its own level or above, never below.

### When a second copy is loaded

Only when it is needed. If the copy already loaded satisfies the version range the module declares for it in `box.json`, the module shares it. A second copy is loaded only when the range is not satisfied. A dependency given as a git or URL reference cannot be compared, so it is shared and reported.

### How a second copy is named

The first copy keeps its name, `qb`. A second copy is named after the module that owns it, `foo/qb`, and its WireBox IDs follow: `QueryBuilder@foo/qb`. Code inside `foo` keeps writing `@qb` and gets `foo`'s copy. The application can ask for a specific copy by its full name. A nested copy that is shared can also be reached by its full name, for example `QueryBuilder@bar/qb`, and that is the same object as `QueryBuilder@qb`.

`/` is safe in these names. Every DSL and event parser in ColdBox splits on `:`, `@` or `.`, and `/` was tested in lock names, thread names, struct keys and URL values on all three engines.

### How injections find the right copy

All copies live in the one existing root injector, each under its own name. The first time WireBox reads an object's `inject` annotations, ColdBox replaces each module name with the copy that the module owning that file should see. A dependency declared in a module's `ModuleConfig` binder is resolved for that module. This happens once per object type. After that, the injection is an ordinary mapping lookup.

Each module that has a second copy, or uses one, gets a binder and an injector that apply the same rule. So `binder.map( "QueryBuilder@qb" )` inside a second copy registers `QueryBuilder@foo/qb`, and `wirebox.getInstance( "QueryBuilder@qb" )` inside `foo` returns `foo`'s copy.

### Settings for a second copy

By its full name, in the application's config:

```cfml
moduleSettings = {
    qb       : { defaultGrammar : "MySQLGrammar@qb" },     // every copy
    "foo/qb" : { defaultGrammar : "SqlServerGrammar@qb" }  // foo's copy only
};
```

`config/modules/foo/qb.cfc` works the same way beside `config/modules/qb.cfc`.

### Class paths

Many modules never use their own class path in code. `cbauth` has no mapping, and `cbi18n`, `cbstorages`, `mixr` and `bcrypt` declare one but never use it. ColdBox can load a second copy of these by its folder path, with no other step.

Modules that do use their own class path, such as `qb`, `quick`, `cbvalidation` and `cbmailservices`, need the rename step. So does a module whose class path is used by another module in the same folder tree: `qb` creates `new cbpaginator.models.Pagination()`.

**The rename command.** A CommandBox task that renames the class path inside one installed copy, so `qb.models.X` becomes `foo__qb.models.X` and the copy's `this.cfmapping = "qb"` becomes `"foo__qb"`. ColdBox then registers that copy under its new mapping like any other module. The task writes a small record file in the folder so it does not rename twice, and so ColdBox can warn at startup when a rename is needed, missing, or was overwritten by an update. Reinstalling the module restores the original files.

This is the approach WordPress plugins use to bundle conflicting library versions (PHP-Scoper, Strauss, Mozart), and the same idea as shading in Java.

### Modules that change WireBox for the whole application

Some modules do more than provide services:

- **Injection keywords.** `quick` adds `quickService:` and `cfmigrations` adds `migrationService:`. A second copy's keyword would apply only inside the module that owns it, the same way module names in `inject` strings are handled. Quick's keyword handler requires a real `Injector` argument, so the injector each module gets must be a real subclass of `Injector`.
- **Listeners on every object WireBox builds.** `mementifier` adds `getMemento()` to every object with a `memento` property. ColdBox knows which module owns each object, so a second copy's listener would handle only objects owned by its module, and the first copy's listener would skip those. Quick's listener only records each entity's WireBox name on the entity, so two copies would not conflict anyway.
- **AOP aspects** match objects across the whole application. These stay single in the first version, until aspect matching can be limited the same way.
- **`cbjavaloader`** stays single. Its Java class loader is shared by the whole server.

A module that stays single is shared, and ColdBox logs why. With `"strict"` it stops startup.

### Effects beyond the module

| A second copy's… | Behaviour |
|---|---|
| interceptors on request points (`preProcess`, `preEvent`, …) | Fire only for requests that belong to the owning module |
| interceptors on start-up and module life-cycle points | Fire as normal |
| application helpers | Not registered again when they match the first copy's. Adobe refuses to declare a function twice, and a helper like `cbauth`'s `auth()` already calls the caller's own `wirebox`, which returns the right copy |
| scheduler | Runs under its own name, `cbScheduler@foo/qb` |
| executors | Shared by name. Unloading one copy does not shut down an executor another module uses |
| `parentSettings` | Only keys the application does not have are added. A different value logs a warning |

### Handlers and views

Library modules are the main need. Second copies of modules with handlers, routes or views come last: they are mounted under their owner's entry point, and `view()`, `runEvent()`, `buildLink()` and similar calls made inside the owner resolve to its copy. Nothing before that step depends on it.

## What changes in WireBox

One optional hook on the `Binder`, empty by default:

- `Mapping.process()` calls it just before a mapping is marked as read, so injection names can be replaced before any thread uses the mapping.
- `Binder.getMapping()` and `mappingExists()` call it when a name is not found, so a full name such as `QueryBuilder@bar/qb` can find the shared copy.

With no hook set, behaviour is unchanged.

## Order of work

Each step is a separate pull request. Steps 3 to 8 change nothing unless the setting is on.

1. Independent bug fixes found during the investigation: COLDBOX-1469 to COLDBOX-1476.
2. Log a warning when a module gets a version outside the range it declares.
3. The WireBox hook above.
4. Let a module be registered under a name that differs from its folder name.
5. The `modules.isolation` setting for library modules, including private injection keywords and listeners limited to their own module's objects.
6. Views use the right copy.
7. The rename command.
8. Handlers, routes and interceptors for second copies.

## What remains global

- `application.wirebox`, `getRootWireBox()` and direct `controller` calls use the first copy.
- External state is shared. Two versions of `cbauth` share one session.
- Objects from two versions can meet in application code, and type checks across copies fail. Use `modules.shared` for a module whose objects cross module boundaries.
- Custom interception points, such as `quickPreSave`, are heard by listeners of both copies.

## The qb experiment

`qb-side-by-side/` reproduces the class path test. It installs qb 13.3.1 as the application's copy and qb 11.1.0 inside a module `foo`, renames the nested copy to `foo__qb`, and builds a query with each. It then checks the file of every object involved: the builder, the grammar and its parent class, the utilities, a new query, a join clause and its parent class, and a raw expression.

From the repository root:

```bash
box task run docs/module-isolation/qb-side-by-side/QbSideBySide.cfc
box run-script start:boxlang
```

Then open `/tests/results/qb-side-by-side/check.cfm`. The output folder is git-ignored.

| Engine | In the request | In a thread |
|---|---|---|
| BoxLang 1.15 (CFML compat) | each copy used only its own files | each copy used only its own files |
| Lucee 5.4 | each copy used only its own files | each copy used only its own files |
| Adobe 2025 | each copy used only its own files | each copy used only its own files |

## Open questions

1. **The overall approach.** Does it make sense, and would you consider pull requests built on it?
2. **The WireBox hook.** Would you prefer a new WireBox event instead? The existing `afterInstanceInspection` fires after the mapping is marked as read, so another thread can already use it.
3. **The rename command.** Is a build command that renames the class path inside one installed copy acceptable? Should it be a separate command, part of `box install`, or a CommandBox module?
4. **BoxLang.** Could BoxLang resolve a mapping based on where the calling file lives, so a file inside `/modules/foo/modules/qb/` gets that folder's `qb`? That would make the rename unnecessary on BoxLang.
5. **Load order.** Nested modules would load in name order when isolation is on, so the first copy is predictable. Is that acceptable, and would you want it always?
6. **`this.moduleInjector`.** Should it stay as it is, move onto the new per-module injector, or be removed?
7. **Modules that must stay single.** Is `cbjavaloader` plus modules with AOP aspects the right list? Is there a module you would expect to break?
