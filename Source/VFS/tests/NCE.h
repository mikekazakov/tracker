// Copyright (C) 2020 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#ifndef NCE
#if __has_include(<.nc_sensitive.h>)
#include <.nc_sensitive.h>
#define NCE(v) (v)
#else
#define NCE(v) ("")
#endif
#endif
