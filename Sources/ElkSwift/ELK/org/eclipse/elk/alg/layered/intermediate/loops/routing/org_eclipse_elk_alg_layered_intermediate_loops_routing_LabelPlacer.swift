import Foundation

package final class org_eclipse_elk_alg_layered_intermediate_loops_routing_LabelPlacer {

    package init() {}

    package func placeLabels(_ slHolder: SelfLoopHolder, _ labelManager: ILabelManager?,
                             _ monitor: IElkProgressMonitor) {
        assignSideAndAlignment(slHolder)

        for slLoop in slHolder.getSLHyperLoops() {
            if slLoop.getSLLabels() != nil {
                if labelManager != nil {
                    manageLabels(slLoop, labelManager!)
                }
                computeCoordinates(slLoop)
            }
        }
    }

    // MARK: - Side and Alignment

    private func assignSideAndAlignment(_ slHolder: SelfLoopHolder) {
        var northernOneSidedSLLoops: [SelfHyperLoop]?
        var southernOneSidedSLLoops: [SelfHyperLoop]?

        let orderingStrategy: SelfLoopOrderingStrategy = slHolder.getLNode().getProperty(
            LayeredOptions.EDGE_ROUTING_SELF_LOOP_ORDERING) as? SelfLoopOrderingStrategy ?? .STACKED
        if orderingStrategy == .SEQUENCED {
            northernOneSidedSLLoops = []
            southernOneSidedSLLoops = []
        }

        for slLoop in slHolder.getSLHyperLoops() {
            guard let slLabels = slLoop.getSLLabels() else { continue }
            guard !slLabels.getLLabels().isEmpty else { continue }
            guard let loopType = slLoop.getSelfLoopType() else { continue }

            switch loopType {
            case .ONE_SIDE:
                let loopSide = slLoop.getOccupiedPortSides().first!

                if orderingStrategy == .SEQUENCED && loopSide == .NORTH {
                    northernOneSidedSLLoops?.append(slLoop)
                } else if orderingStrategy == .SEQUENCED && loopSide == .SOUTH {
                    southernOneSidedSLLoops?.append(slLoop)
                } else {
                    assignOneSidedSimpleSideAndAlignment(slLoop, loopSide)
                }

            case .TWO_SIDES_CORNER:
                assignTwoSidesCornerSideAndAlignment(slLoop)

            case .TWO_SIDES_OPPOSING, .THREE_SIDES:
                assignTwoSidesOpposingAndThreeSidesSideAndAlignment(slLoop)

            case .FOUR_SIDES:
                assignFourSidesSideAndAlignment(slLoop)
            }
        }

        if let northLoops = northernOneSidedSLLoops, !northLoops.isEmpty {
            assignOneSidedSequencedSideAndAlignment(northLoops, .NORTH)
        }
        if let southLoops = southernOneSidedSLLoops, !southLoops.isEmpty {
            assignOneSidedSequencedSideAndAlignment(southLoops, .SOUTH)
        }
    }

    private func assignOneSidedSimpleSideAndAlignment(_ slLoop: SelfHyperLoop, _ loopSide: PortSide) {
        for label in slLoop.getSLLabels()!.getLLabels() {
            _ = label.setProperty(LayeredOptions.EDGE_LABELS_INLINE, nil)
        }

        switch loopSide {
        case .EAST, .WEST:
            var topmostPort = slLoop.getLeftmostPort()!
            if slLoop.getRightmostPort()!.getLPort().getPosition().y < topmostPort.getLPort().getPosition().y {
                topmostPort = slLoop.getRightmostPort()!
            }
            assignSideAndAlignmentHelper(slLoop, loopSide, .TOP, topmostPort)

        case .NORTH, .SOUTH:
            assignSideAndAlignmentHelper(slLoop, loopSide, .CENTER, nil)

        default:
            break
        }
    }

    private func assignOneSidedSequencedSideAndAlignment(_ slLoops: [SelfHyperLoop], _ portSide: PortSide) {
        var slLoops = slLoops
        guard !slLoops.isEmpty else { return }

        var id = 0
        for lPort in slLoops[0].getSLHolder().getLNode().getPorts() {
            lPort.id = id
            id += 1
        }

        if portSide == .NORTH {
            slLoops.sort { $0.getLeftmostPort()!.getLPort().id < $1.getLeftmostPort()!.getLPort().id }
        } else {
            slLoops.sort { $0.getLeftmostPort()!.getLPort().id > $1.getLeftmostPort()!.getLPort().id }
        }

        var leftIdx = 0
        var rightIdx = slLoops.count - 1

        while leftIdx < rightIdx {
            let leftSlLoop = slLoops[leftIdx]
            let rightSlLoop = slLoops[rightIdx]

            let leftLoopAlignmentRef = portSide == .NORTH ? leftSlLoop.getRightmostPort()! : leftSlLoop.getLeftmostPort()!
            let rightLoopAlignmentRef = portSide == .NORTH ? rightSlLoop.getLeftmostPort()! : rightSlLoop.getRightmostPort()!

            assignSideAndAlignmentHelper(leftSlLoop, portSide, .RIGHT, leftLoopAlignmentRef)
            assignSideAndAlignmentHelper(rightSlLoop, portSide, .LEFT, rightLoopAlignmentRef)

            leftIdx += 1
            rightIdx -= 1
        }

        if leftIdx == rightIdx {
            assignSideAndAlignmentHelper(slLoops[leftIdx], portSide, .CENTER, nil)
        }
    }

    private func assignTwoSidesCornerSideAndAlignment(_ slLoop: SelfHyperLoop) {
        let leftmostPortSide = slLoop.getLeftmostPort()!.getLPort().getSide()
        let rightmostPortSide = slLoop.getRightmostPort()!.getLPort().getSide()

        for label in slLoop.getSLLabels()!.getLLabels() {
            _ = label.setProperty(LayeredOptions.EDGE_LABELS_INLINE, nil)
        }

        if leftmostPortSide == .NORTH {
            assignSideAndAlignmentHelper(slLoop, .NORTH, .LEFT, slLoop.getLeftmostPort())
        } else if rightmostPortSide == .NORTH {
            assignSideAndAlignmentHelper(slLoop, .NORTH, .RIGHT, slLoop.getRightmostPort())
        } else if leftmostPortSide == .SOUTH {
            assignSideAndAlignmentHelper(slLoop, .SOUTH, .RIGHT, slLoop.getLeftmostPort())
        } else if rightmostPortSide == .SOUTH {
            assignSideAndAlignmentHelper(slLoop, .SOUTH, .LEFT, slLoop.getRightmostPort())
        }
    }

    private func assignTwoSidesOpposingAndThreeSidesSideAndAlignment(_ slLoop: SelfHyperLoop) {
        let occupiedSides = slLoop.getOccupiedPortSides()
        var hasInlineLabels = false
        for label in slLoop.getSLLabels()!.getLLabels() {
            if let inline: Bool = label.getProperty(LayeredOptions.EDGE_LABELS_INLINE) as? Bool, inline {
                hasInlineLabels = true
                break
            }
        }

        if !occupiedSides.contains(.NORTH) {
            assignSideAndAlignmentHelper(slLoop, .SOUTH, .CENTER, nil)
        } else if !occupiedSides.contains(.SOUTH) {
            assignSideAndAlignmentHelper(slLoop, .NORTH, .CENTER, nil)
        } else if !occupiedSides.contains(.WEST) {
            assignSideAndAlignmentHelper(slLoop,
                hasInlineLabels ? .EAST : .NORTH,
                hasInlineLabels ? .CENTER : .LEFT,
                hasInlineLabels ? nil : slLoop.getLeftmostPort())
        } else if !occupiedSides.contains(.EAST) {
            assignSideAndAlignmentHelper(slLoop,
                hasInlineLabels ? .WEST : .NORTH,
                hasInlineLabels ? .CENTER : .RIGHT,
                hasInlineLabels ? nil : slLoop.getRightmostPort())
        }
    }

    private func assignFourSidesSideAndAlignment(_ slLoop: SelfHyperLoop) {
        let leftmostPortSide = slLoop.getLeftmostPort()!.getLPort().getSide()
        let rightmostPortSide = slLoop.getLeftmostPort()!.getLPort().getSide() // Note: Java uses getLeftmostPort() for both

        for label in slLoop.getSLLabels()!.getLLabels() {
            _ = label.setProperty(LayeredOptions.EDGE_LABELS_INLINE, nil)
        }

        if leftmostPortSide == .NORTH || rightmostPortSide == .NORTH {
            assignSideAndAlignmentHelper(slLoop, .SOUTH, .CENTER, nil)
        } else {
            assignSideAndAlignmentHelper(slLoop, .NORTH, .CENTER, nil)
        }
    }

    private func assignSideAndAlignmentHelper(_ slLoop: SelfHyperLoop, _ side: PortSide,
                                                _ alignment: SelfHyperLoopLabels.Alignment,
                                                _ alignmentReference: SelfLoopPort?) {
        let slLabels = slLoop.getSLLabels()!
        slLabels.setSide(side)
        slLabels.setAlignment(alignment)
        slLabels.setAlignmentReferenceSLPort(alignmentReference)
    }

    // MARK: - Label Management

    private func manageLabels(_ slLoop: SelfHyperLoop, _ labelManager: ILabelManager) {
        let slLabels = slLoop.getSLLabels()!
        let alignRef = slLabels.getAlignmentReferenceSLPort()

        let lNode = slLoop.getSLHolder().getLNode()
        let lNodeSize = lNode.getSize()
        let lNodeMargins = slLoop.getSLHolder().getLNode().getMargin()

        var targetWidth: Double = 0

        switch slLabels.getAlignment() {
        case .CENTER:
            targetWidth = lNodeMargins.left + lNodeSize.x + lNodeMargins.right
        case .LEFT:
            targetWidth = lNodeSize.x
                - alignRef!.getLPort().getPosition().x - alignRef!.getLPort().getAnchor().x
                + lNodeMargins.right
        case .RIGHT:
            targetWidth = lNodeMargins.left + alignRef!.getLPort().getPosition().x + alignRef!.getLPort().getAnchor().x
        case .TOP:
            targetWidth = org_eclipse_elk_alg_layered_intermediate_LabelManagementProcessor.MIN_WIDTH_EDGE_LABELS
        }

        slLabels.applyLabelManagement(
            labelManager,
            max(targetWidth, org_eclipse_elk_alg_layered_intermediate_LabelManagementProcessor.MIN_WIDTH_EDGE_LABELS))
    }

    // MARK: - Coordinate Computation

    private func computeCoordinates(_ slLoop: SelfHyperLoop) {
        let slLabels = slLoop.getSLLabels()!
        let alignRef = slLabels.getAlignmentReferenceSLPort()
        let size = slLabels.getSize()
        let pos = slLabels.getPosition()

        switch slLabels.getAlignment() {
        case .CENTER:
            pos.x = (slLoop.getSLHolder().getLNode().getSize().x - size.x) / 2
        case .LEFT:
            pos.x = alignRef!.getLPort().getPosition().x + alignRef!.getLPort().getAnchor().x
        case .RIGHT:
            pos.x = alignRef!.getLPort().getPosition().x + alignRef!.getLPort().getAnchor().x - size.x
        case .TOP:
            pos.y = alignRef!.getLPort().getPosition().y + alignRef!.getLPort().getAnchor().y
        }
    }
}
