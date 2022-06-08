/*---------------------------------------------------------------------------------------------
* Copyright (c) Bentley Systems, Incorporated. All rights reserved.
* See LICENSE.md in the project root for license terms and full copyright notice.
*--------------------------------------------------------------------------------------------*/

import Foundation

/// Custom subclass of the ModelApplication class. That class is shared by all the samples. This one takes care of the custom behavior
/// that is specific to this sample.
class CamModelApplication: ModelApplication {
    /// Gets custom URL hash parameters to be passed when loading the frontend.
    /// This override adds `isCameraSample=true` to the list or params from super.
    /// - Returns: The hash params from super, with `isCameraSample=true` added.
    override func getUrlHashParams() -> HashParams {
        var hashParams = super.getUrlHashParams()
        hashParams.append(HashParam(name: "isCameraSample", value: true))
        return hashParams
    }
}
