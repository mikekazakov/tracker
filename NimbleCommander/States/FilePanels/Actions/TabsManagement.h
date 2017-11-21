// Copyright (C) 2017 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include "DefaultAction.h"

namespace nc::panel::actions {

struct ShowNextTab final : StateAction
{
    bool Predicate( MainWindowFilePanelState *_target ) const override;
    bool ValidateMenuItem( MainWindowFilePanelState *_target, NSMenuItem *_item ) const override;
    void Perform( MainWindowFilePanelState *_target, id _sender ) const override;
};

struct ShowPreviousTab final : StateAction
{
    bool Predicate( MainWindowFilePanelState *_target ) const override;
    bool ValidateMenuItem( MainWindowFilePanelState *_target, NSMenuItem *_item ) const override;
    void Perform( MainWindowFilePanelState *_target, id _sender ) const override;
};
    
struct AddNewTab final : StateAction
{
    void Perform( MainWindowFilePanelState *_target, id _sender ) const override;
};

struct CloseTab final : StateAction
{
    bool ValidateMenuItem( MainWindowFilePanelState *_target, NSMenuItem *_item ) const override;    
    void Perform( MainWindowFilePanelState *_target, id _sender ) const override;
};
    
struct CloseWindow final : StateAction
{
    bool ValidateMenuItem( MainWindowFilePanelState *_target, NSMenuItem *_item ) const override;    
    void Perform( MainWindowFilePanelState *_target, id _sender ) const override;
};
    
namespace context {

struct AddNewTab final : StateAction
{
    AddNewTab(PanelController *_current_pc);
    void Perform( MainWindowFilePanelState *_target, id _sender ) const override;
private:
    PanelController *m_CurrentPC;
};
    
}
    
}
