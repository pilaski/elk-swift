import Foundation

package final class org_eclipse_elk_alg_layered_intermediate_LongEdgeJoiner {
    package init() {}

    package func process(_ layeredGraph: LGraph, _ monitor: IElkProgressMonitor) {
        _ = monitor.begin("Edge joining", 1)

        let addUnnecessaryBendpoints = layeredGraph.getProperty(LayeredOptions.UNNECESSARY_BENDPOINTS) as? Bool ?? false

        for layer in layeredGraph.layers {
            var i = 0
            while i < layer.nodes.count {
                let node = layer.nodes[i]
                if node.type == .longEdge {
                    org_eclipse_elk_alg_layered_intermediate_LongEdgeJoiner.joinAt(node, addUnnecessaryBendpoints)
                    layer.nodes.remove(at: i)
                } else {
                    i += 1
                }
            }
        }

        monitor.done()
    }

    package static func joinAt(_ longEdgeDummy: LNode, _ addUnnecessaryBendpoints: Bool) {
        guard let inputPort = longEdgeDummy.getPorts(PortSide.WEST).first,
              let outputPort = longEdgeDummy.getPorts(PortSide.EAST).first else {
            // Defensive: skip dummy nodes with unexpected port sides
            return
        }
        let inputPortEdges = inputPort.incomingEdges
        let outputPortEdges = outputPort.outgoingEdges
        var edgeCount = inputPortEdges.count

        let unnecessaryBendpoint = longEdgeDummy.ports[0].getAbsoluteAnchor()

        while edgeCount > 0 {
            edgeCount -= 1

            let survivingEdge = inputPortEdges[0]
            let droppedEdge = outputPortEdges[0]

            let targetIncomingEdges = droppedEdge.target!.incomingEdges
            let droppedEdgeListIndex = targetIncomingEdges.firstIndex(where: { $0 === droppedEdge }) ?? 0
            survivingEdge.setTargetAndInsertAtIndex(droppedEdge.target, droppedEdgeListIndex)

            droppedEdge.setSource(nil)
            droppedEdge.setTarget(nil)

            let survivingBendPoints = survivingEdge.getBendPoints()

            if addUnnecessaryBendpoints {
                survivingBendPoints.add(KVector(unnecessaryBendpoint))
            }

            for bendPoint in droppedEdge.getBendPoints() {
                survivingBendPoints.add(KVector(bendPoint))
            }

            for label in droppedEdge.labels {
                survivingEdge.labels.append(label)
            }

            let survivingJunctionPoints = survivingEdge.getProperty(LayeredOptions.JUNCTION_POINTS) as? KVectorChain
            let droppedJunctionPoints = droppedEdge.getProperty(LayeredOptions.JUNCTION_POINTS) as? KVectorChain
            if let droppedJP = droppedJunctionPoints {
                var sjp = survivingJunctionPoints
                if sjp == nil {
                    sjp = KVectorChain()
                    survivingEdge.setProperty(LayeredOptions.JUNCTION_POINTS, value: sjp!)
                }
                for jp in droppedJP {
                    sjp!.add(KVector(jp))
                }
            }
        }
    }
}
