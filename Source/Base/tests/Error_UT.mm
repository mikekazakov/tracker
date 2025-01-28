// Copyright (C) 2025 Michael Kazakov. Subject to GNU General Public License version 3.
#include "UnitTests_main.h"
#include <Base/Error.h>
#include <fmt/format.h>
#include <Security/Security.h>
#include <AudioToolbox/AudioToolbox.h>
#include <mach/kern_return.h>

using namespace nc;
using base::ErrorDescriptionProvider;

#define PREFIX "nc::Error "

struct ErrorDescriptionProviderAutoReg {
public:
    ErrorDescriptionProviderAutoReg(std::string_view _domain, std::shared_ptr<const ErrorDescriptionProvider> _provider)
        : m_Domain(_domain)
    {
        m_Previous = Error::DescriptionProvider(_domain);
        Error::DescriptionProvider(_domain, _provider);
    }

    ~ErrorDescriptionProviderAutoReg() { Error::DescriptionProvider(m_Domain, m_Previous); }

private:
    std::string m_Domain;
    std::shared_ptr<const ErrorDescriptionProvider> m_Previous;
};

TEST_CASE(PREFIX "Domain and error code are preserved")
{
    Error err("some domain", 42);
    CHECK(err.Domain() == "some domain");
    CHECK(err.Code() == 42);
}

TEST_CASE(PREFIX "Description can be synthesized")
{
    Error err("Hello", 42);
    CHECK(err.Description() == "Error Domain=Hello Code=42");
}

TEST_CASE(PREFIX "Description can query additional information from a provider")
{
    struct Provider : ErrorDescriptionProvider {
        std::string Description(int64_t _code) const noexcept override { return fmt::format("Description #{}", _code); }
    };
    ErrorDescriptionProviderAutoReg autoreg("Hello", std::make_shared<Provider>());

    Error err("Hello", 57);
    CHECK(err.Description() == "Error Domain=Hello Code=57 \"Description #57\"");
}

TEST_CASE(PREFIX "Querying failure reason")
{
    struct Provider : ErrorDescriptionProvider {
        std::string LocalizedFailureReason(int64_t _code) const noexcept override
        {
            return fmt::format("Reason#{}", _code);
        }
    };

    ErrorDescriptionProviderAutoReg autoreg("MyDomain", std::make_shared<Provider>());

    SECTION("From provider")
    {
        Error err("MyDomain", 42);
        CHECK(err.LocalizedFailureReason() == "Reason#42");
    }
    SECTION("From payload")
    {
        Error err("MyDomain", 42);
        err.LocalizedFailureReason("something bad!");
        CHECK(err.LocalizedFailureReason() == "something bad!");

        // Check COW behaviour
        Error err2 = err;
        CHECK(err.LocalizedFailureReason() == "something bad!");
        CHECK(err2.LocalizedFailureReason() == "something bad!");
        err2.LocalizedFailureReason("wow!");
        CHECK(err.LocalizedFailureReason() == "something bad!");
        CHECK(err2.LocalizedFailureReason() == "wow!");
    }
    SECTION("None available")
    {
        Error err("Nonsense", 42);
        CHECK(err.LocalizedFailureReason() == "Unknown");
    }
}

TEST_CASE(PREFIX "Description providers can be set and unset")
{
    struct Provider : ErrorDescriptionProvider {
        std::string Description(int64_t) const noexcept override { return fmt::format("Hi"); }
    };

    Error err("Hello", 57);
    CHECK(err.Description() == "Error Domain=Hello Code=57");
    {
        ErrorDescriptionProviderAutoReg autoreg("Hello", std::make_shared<Provider>());
        CHECK(err.Description() == "Error Domain=Hello Code=57 \"Hi\"");
    }
    CHECK(err.Description() == "Error Domain=Hello Code=57");
}

TEST_CASE(PREFIX "Predefined domains have description providers")
{
    CHECK(Error(Error::POSIX, EINTR).LocalizedFailureReason() == "Interrupted system call");

    CHECK(Error(Error::POSIX, ENFILE).LocalizedFailureReason() == "Too many open files in system");

    CHECK(Error(Error::OSStatus, errSecDiskFull).LocalizedFailureReason() ==
          "The operation couldn’t be completed. (OSStatus error -34.)");

    CHECK(Error(Error::OSStatus, kAudioServicesSystemSoundExceededMaximumDurationError).LocalizedFailureReason() ==
          "The operation couldn’t be completed. (OSStatus error -1502.)");

    CHECK(Error(Error::Mach, KERN_INVALID_ARGUMENT).LocalizedFailureReason() ==
          "The operation couldn’t be completed. (Mach error 4 - (os/kern) invalid argument)");

    CHECK(Error(Error::Mach, kIOReturnVMError).LocalizedFailureReason() ==
          "The operation couldn’t be completed. (Mach error -536870200 - (iokit/common) misc. VM failure)");

    CHECK(Error(Error::Cocoa, NSFileReadCorruptFileError).LocalizedFailureReason() ==
          "The file isn’t in the correct format.");

    CHECK(Error(Error::Cocoa, NSXPCConnectionInterrupted).LocalizedFailureReason() ==
          "Couldn’t communicate with a helper application.");
}

TEST_CASE(PREFIX "Can interface with NSError")
{
    {
        NSError *const ns_err = [NSError errorWithDomain:NSCocoaErrorDomain
                                                    code:NSPropertyListReadUnknownVersionError
                                                userInfo:nil];
        const Error err(ns_err);
        CHECK(err.Domain() == Error::Cocoa);
        CHECK(err.Code() == NSPropertyListReadUnknownVersionError);
        CHECK(err.LocalizedFailureReason() == "The data is in a format that this application doesn’t understand.");
    }
    {
        NSError *const ns_err = [NSError errorWithDomain:NSCocoaErrorDomain
                                                    code:NSPropertyListReadUnknownVersionError
                                                userInfo:@{NSLocalizedFailureReasonErrorKey: @"Hola! 😸"}];
        const Error err(ns_err);
        CHECK(err.Domain() == Error::Cocoa);
        CHECK(err.Code() == NSPropertyListReadUnknownVersionError);
        CHECK(err.LocalizedFailureReason() == "Hola! 😸");
    }
}
