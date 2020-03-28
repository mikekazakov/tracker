// Copyright (C) 2020 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include <span>
#include <functional>

#include "Parser2.h"

namespace nc::term {

class Interpreter
{
public:
    using Bytes = std::span<const std::byte>;
    using Input = std::span<const input::Command>;
    using Output = std::function<void(Bytes _bytes)>;

    virtual ~Interpreter() = default;
    virtual void Interpret( Input _to_interpret ) = 0;
    virtual void SetOuput( Output _output ) = 0;
};

}
