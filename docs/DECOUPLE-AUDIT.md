# DECOUPLE-AUDIT — View 直接操作 modelContext 清单

> 扫描基准:VPS main(10534ee)+ GitHub main 渲染 commit 合并后的代码。
> 已解耦不重做:WorldBookPanelView、MemoryPanelView、MemorySettingsTab、SidebarView(参考 885d95d / 3af3949 / 9c8b18e)。
> 判定标准:View 里直接 `modelContext.insert/delete/save/fetch/fetchCount` 才算;把 modelContext 当参数传给 Service/Store/ViewModel 的不算(那是正常 DI)。

## 一、待解耦清单(优先级从高到低)

### 1. CardFlowView.swift(核心聊天视图,2133 行)→ ConversationListStore
| 行号 | 操作 | 去向 |
|---|---|---|
| 1832 | `modelContext.insert(item)` 收藏消息到标签(FavoriteItem) | `ConversationListStore.insertFavorite`(已有) |
| 1868 | `modelContext.insert(tag)` 新建 ConversationTag | `ConversationListStore.insertTag`(已有) |
| 2069 | `modelContext.delete(item)` toggleTag 取消挂标签 | `ConversationListStore.deleteFavorite`(新增,只 delete 不显式 save,保持 autosave 语义) |
| 2078 | `modelContext.fetch(convDescriptor)` 查对话标题做 preview | `ConversationListStore.conversation(id:profileId:)`(已有) |
| 2089 | `modelContext.insert(item)` toggleTag 挂标签 | `ConversationListStore.insertFavorite`(已有) |

### 2. ContentView.swift(根视图,958 行)→ ConversationListStore
| 行号 | 操作 | 去向 |
|---|---|---|
| 208 | `modelContext.fetch` 按 id 查 probe 对话(DEBUG) | `ConversationListStore.conversation(id:)`(新增跨楼层版) |
| 378 | `modelContext.fetch` 推送通知跳转按 id 查对话 | 同上 |
| 745 | `modelContext.fetchCount` 判断楼层是否没有对话 | `ConversationListStore.hasActiveConversations(profileId:)`(新增) |

### 3. GeneralSettingsTab.swift → WorldBookStore
| 行号 | 操作 | 去向 |
|---|---|---|
| 106 | `modelContext.fetch(wbDescriptor)` 当前楼层世界书(**在 body 渲染路径里 fetch**) | `WorldBookStore.fetchBooks`(已有) |
| 175/180 | `modelContext.delete(book)` + `try modelContext.save()` 删世界书 | `WorldBookStore.delete`(已有) |
| 238/239 | `modelContext.delete(book)` + save 删孤儿世界书 | `WorldBookStore.delete`(已有) |
| 255 | `modelContext.fetch(allDescriptor)` 全量世界书(孤儿清理) | `WorldBookStore.fetchAllBooks`(新增) |

### 4. PersonaSettingsTab.swift → WorldBookStore
| 行号 | 操作 | 去向 |
|---|---|---|
| 842 | `modelContext.fetch(wbDescriptor)` 组装预览取世界书 | `WorldBookStore.fetchBooks`(已有) |
| 921 | `modelContext.fetch(wbDescriptor2)` 请求预览取世界书 | 同上 |

### 5. 贴纸家族 → StickerViewModel(它已是贴纸数据层,所有方法都收 context 参数)
| 文件 | 行号 | 操作 | 去向 |
|---|---|---|---|
| StickerToolbar.swift | 110/112 | insert StickerAsset + save(画画保存) | `StickerViewModel.addDrawingAsset`(新增,顺带消灭三处重复) |
| StickerKeyboardPanel.swift | 150/152 | insert + save(画画保存,重复代码) | 同上 |
| StickerLibraryView.swift | 156/158 | insert + save(画画保存,重复代码) | 同上 |
| StickerGestureOverlay.swift | 289/320/350 | `try? parent.modelContext.save()` 手势结束落盘 | `StickerViewModel.persist`(新增) |
| StickerCanvasLayer.swift | 59/106 | `try? modelContext.save()` 选框 onSave / 便签编辑落盘 | `StickerViewModel.persist` |
| StickerSettingsTab.swift | 105/110/253/258 | fetch 全量数组只为 `.count`(×4) | `StickerViewModel.assetCount/placedCount`(新增,改用 `fetchCount`) |

### 6. ProjectsView.swift → ProjectStore(新建)
| 行号 | 操作 | 去向 |
|---|---|---|
| 135 | `modelContext.delete(project)` | `ProjectStore.delete` |
| 168 | `modelContext.insert(project)` | `ProjectStore.insert` |

### 7. ConsoleView.swift → DailyContextStore(新建)
| 行号 | 操作 | 去向 |
|---|---|---|
| 55 | `modelContext.insert(ctx)` 确保今日 DailyContext 存在 | `DailyContextStore.ensureToday` |

### 8. CCSessionPickerSheet.swift → ConversationListStore
| 行号 | 操作 | 去向 |
|---|---|---|
| 193 | `modelContext.fetch` 全表扫 Conversation 建 session→title 映射 | `ConversationListStore.ccSessionOwners`(新增) |

### 9. 已解耦文件的残留(MemoryPanelView)
| 行号 | 操作 | 去向 |
|---|---|---|
| 409 | `try? modelContext.save()` reviveMemory 复活记忆 | `SwiftDataMemoryStore.revive`(新增) |
| 420 | `modelContext.fetch(convDesc)` jumpToSource 查源对话 | `ConversationListStore.conversation(id:profileId:)`(已有) |

### 不算违规、不动的(正常 DI / container 传递)
- ImportView:554、ImportHistoryView:89 — 只取 `modelContext.container` 传给后台 importer
- ExportOptionsSheet:133、DataSettingsTab:37/44、CalendarPanelView:210、StickerImportSheet:171/188 — 把 context 传给 Service/VM
- BranchMapSheet、SettingsView、RegexSettingsTab、PagingContainerView — 只声明/转发,无直接操作
- SidebarView / WorldBookPanelView / MemorySettingsTab 的 modelContext 引用全部是传给 Store 的参数,无直接操作 ✓

## 二、其他代码质量问题

1. **重复逻辑:画画保存三连抄**。`StickerToolbar` / `StickerKeyboardPanel` / `StickerLibraryView` 三处几乎逐字相同的 DrawingBoardSheet 回调(saveStickerImage → StickerAsset → insert → 插数组 → save)。本次随解耦合并为 `StickerViewModel.addDrawingAsset`。
2. **重复逻辑:StickerSettingsTab 同文件双胞胎**。`loadStickerStats()`(StickerSettingsTab)和 `loadStats()`(IOSStickerPage)逐字相同,两个 struct 各抄一份统计逻辑。本次抽到 StickerViewModel 后两边共用。
3. **性能:用全量 fetch 数个数**。StickerSettingsTab 4 处 `(try? modelContext.fetch(desc))?.count`,应该用 `fetchCount`(本次已改)。
4. **性能:CCSessionPickerSheet 全表扫描**。`FetchDescriptor<Conversation>()` 无谓词拉全库所有对话(含已删除、跨楼层)再内存过滤,对话多时卡 sheet。本次在 Store 层保留行为,谓词下推留 TODO(`ccBridgeSessionName` 谓词 + isDeleted 过滤可下推)。
5. **性能:body 渲染路径里做 fetch**。GeneralSettingsTab:106(每次 body 重算都查库)、PersonaSettingsTab:842/921(在 ViewBuilder 里跑 PromptAssembler.assemble + TokenEstimator,组装预览每帧重算)。解耦后仍在 body 里,建议后续挪到 onAppear/@State。
6. **死代码:ContentView.normalLayout(751 行起)**。注释写着 "MARK: - macOS Layout",定义后全文无任何调用点。macOS target 清除时的残留,可整块删除(连带它引用的参数传递)。
7. **God View 残留**:SidebarView 2597 行、CardFlowView 2133 行、ContentView 958 行。数据操作解耦后,SidebarView/CardFlowView 还塞着大量子 View(sheet、capsule、row)同文件,建议按子 View 拆文件(纯移动,无逻辑改动)。
8. **ConversationListStore.fetchPage 的 tag 路径在内存里过滤分页**(fetch 全部再 prefix(pageSize)),FavoriteItem→Conversation 没有关系建模导致谓词没法 join。规模大了要么建关系要么两段查询取 id 集合下推谓词。
9. **流程风险:VPS main 与 GitHub main 分叉**。解耦三连 commit(885d95d/3af3949/9c8b18e)和 push 调试 commit 只在 VPS,渲染混合方案两边各自演化(47e2d56 vs 5c25c91)且 GitHub 侧是旧版。本分支已把两边合上(冲突取 VPS 新版),后续记得 VPS 及时 push。
10. **MemoryCompat.swift / SC-B2 stubs**:8d74ffb/6e301d5 加的兼容 stub(CacheDiagLog 单例等)是为编译过渡,确认功能落地后应清理。

## 三、执行状态

- [ ] CardFlowView → ConversationListStore
- [ ] ContentView → ConversationListStore
- [ ] GeneralSettingsTab → WorldBookStore
- [ ] PersonaSettingsTab → WorldBookStore
- [ ] StickerViewModel 增 addDrawingAsset/persist/counts + 六个贴纸 View 接入
- [ ] ProjectsView → ProjectStore(新)
- [ ] ConsoleView → DailyContextStore(新)
- [ ] CCSessionPickerSheet → ConversationListStore
- [ ] MemoryPanelView 残留清理
