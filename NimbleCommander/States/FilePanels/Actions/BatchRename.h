#pragma once

#include "DefaultAction.h"

@class PanelController;

namespace panel::actions {

struct BatchRename : DefaultPanelAction
{
    static bool Predicate( PanelController *_target );
    static bool ValidateMenuItem( PanelController *_target, NSMenuItem *_item );
    static void Perform( PanelController *_target, id _sender );
};


}
