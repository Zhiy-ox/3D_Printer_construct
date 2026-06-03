function layers = slice_mesh(F, V, zPlanes, tol)
% SLICE_MESH  Slice a triangle mesh at specified Z planes (vectorized).
%
%   layers = slice_mesh(F, V, zPlanes, tol)
%
% INPUTS:
%   F        - Nx3 face connectivity (triangle indices into V)
%   V        - Mx3 vertex coordinates [x y z]
%   zPlanes  - 1xL vector of Z heights to slice at (mm)
%   tol      - Geometric tolerance (mm), default 1e-9
%
% OUTPUT:
%   layers   - 1xL cell array. layers{i} is a Kx4 matrix [x1 y1 x2 y2]
%              of 2D contour line segments at zPlanes(i).
%              Empty matrix if no intersections at that Z.
%
% This version uses vectorized edge-plane intersection for speed on
% large meshes. It handles:
%   - Standard edge crossings
%   - Vertex-on-plane cases
%   - Degenerate triangles
%   - Coplanar edges (skipped)
%
% See also: hatch_layer, build_toolpath, import_model

    if nargin < 4 || isempty(tol)
        tol = 1e-9;
    end

    nLayers = numel(zPlanes);
    nFaces  = size(F, 1);
    layers  = cell(1, nLayers);

    % ---- Precompute all triangle vertex data ----
    % Extract XYZ for each vertex of each face
    v1 = V(F(:,1), :);  % nFaces x 3
    v2 = V(F(:,2), :);
    v3 = V(F(:,3), :);

    z1 = v1(:,3);  z2 = v2(:,3);  z3 = v3(:,3);
    triZmin = min(min(z1, z2), z3);
    triZmax = max(max(z1, z2), z3);

    % ---- Edge definitions: 3 edges per triangle ----
    % Edge A: v1->v2,  Edge B: v2->v3,  Edge C: v3->v1
    eA_p1 = v1;  eA_p2 = v2;  eA_dz = z2 - z1;
    eB_p1 = v2;  eB_p2 = v3;  eB_dz = z3 - z2;
    eC_p1 = v3;  eC_p2 = v1;  eC_dz = z1 - z3;

    for li = 1:nLayers
        z = zPlanes(li);

        % ---- Quick reject: triangles not spanning this Z ----
        candidates = (triZmax >= z - tol) & (triZmin <= z + tol);
        if ~any(candidates)
            layers{li} = zeros(0, 4);
            continue;
        end

        cidx = find(candidates);
        nCand = numel(cidx);

        % ---- Vectorized edge intersection ----
        % For each candidate triangle, compute intersection on each edge

        % Signed distances for this Z
        d1 = z1(cidx) - z;  d2 = z2(cidx) - z;  d3 = z3(cidx) - z;

        % Process each edge: find parametric t where edge crosses z
        % Edge A: v1->v2
        dzA = eA_dz(cidx);
        tA  = -d1 ./ dzA;  % t where z = plane
        validA = abs(dzA) > tol & tA >= -tol & tA <= 1 + tol;
        % Intersection point
        pA_x = eA_p1(cidx,1) + tA .* (eA_p2(cidx,1) - eA_p1(cidx,1));
        pA_y = eA_p1(cidx,2) + tA .* (eA_p2(cidx,2) - eA_p1(cidx,2));

        % Edge B: v2->v3
        dzB = eB_dz(cidx);
        tB  = -d2 ./ dzB;
        validB = abs(dzB) > tol & tB >= -tol & tB <= 1 + tol;
        pB_x = eB_p1(cidx,1) + tB .* (eB_p2(cidx,1) - eB_p1(cidx,1));
        pB_y = eB_p1(cidx,2) + tB .* (eB_p2(cidx,2) - eB_p1(cidx,2));

        % Edge C: v3->v1
        dzC = eC_dz(cidx);
        tC  = -d3 ./ dzC;
        validC = abs(dzC) > tol & tC >= -tol & tC <= 1 + tol;
        pC_x = eC_p1(cidx,1) + tC .* (eC_p2(cidx,1) - eC_p1(cidx,1));
        pC_y = eC_p1(cidx,2) + tC .* (eC_p2(cidx,2) - eC_p1(cidx,2));

        % ---- Fast path: triangles with exactly 2 valid edge crossings (99% of cases) ----
        maskAB = validA & validB & ~validC;
        maskAC = validA & validC & ~validB;
        maskBC = validB & validC & ~validA;

        fastSegs = [ ...
            pA_x(maskAB) pA_y(maskAB) pB_x(maskAB) pB_y(maskAB); ...
            pA_x(maskAC) pA_y(maskAC) pC_x(maskAC) pC_y(maskAC); ...
            pB_x(maskBC) pB_y(maskBC) pC_x(maskBC) pC_y(maskBC)];

        % Drop zero-length segments (plane grazing a shared vertex makes the two
        % edge intersections coincide); the original per-triangle dedup did this.
        if ~isempty(fastSegs)
            fastLen2 = (fastSegs(:,1)-fastSegs(:,3)).^2 + (fastSegs(:,2)-fastSegs(:,4)).^2;
            fastSegs = fastSegs(fastLen2 > tol^2, :);
        end

        % ---- Slow path: degenerate triangles (vertex-on-plane, all 3 edges, etc.) ----
        degenIdx = find(~(maskAB | maskAC | maskBC));
        slowSegs = zeros(numel(degenIdx), 4);
        slowCount = 0;

        for ci = degenIdx(:).'
            pts = zeros(0, 2);
            if validA(ci), pts(end+1,:) = [pA_x(ci), pA_y(ci)]; end %#ok<AGROW>
            if validB(ci), pts(end+1,:) = [pB_x(ci), pB_y(ci)]; end %#ok<AGROW>
            if validC(ci), pts(end+1,:) = [pC_x(ci), pC_y(ci)]; end %#ok<AGROW>
            if ~validA(ci) && abs(d1(ci)) <= tol
                pts(end+1,:) = [eA_p1(cidx(ci),1), eA_p1(cidx(ci),2)]; %#ok<AGROW>
            end
            if ~validA(ci) && abs(d2(ci)) <= tol
                pts(end+1,:) = [eA_p2(cidx(ci),1), eA_p2(cidx(ci),2)]; %#ok<AGROW>
            end
            if ~validB(ci) && abs(d3(ci)) <= tol
                pts(end+1,:) = [eB_p2(cidx(ci),1), eB_p2(cidx(ci),2)]; %#ok<AGROW>
            end
            if size(pts, 1) < 2, continue; end
            ptsR = round(pts / tol) * tol;
            [~, ia] = unique(ptsR, 'rows', 'stable');
            pts = pts(ia, :);
            if size(pts, 1) < 2, continue; end
            if size(pts, 1) == 2
                pFar1 = pts(1,:);  pFar2 = pts(2,:);
            else
                dmax = -inf; ia2 = 1; ib2 = 2;
                for a = 1:size(pts,1)-1
                    for b = a+1:size(pts,1)
                        dd = sum((pts(a,:)-pts(b,:)).^2);
                        if dd > dmax, dmax = dd; ia2 = a; ib2 = b; end
                    end
                end
                pFar1 = pts(ia2,:);  pFar2 = pts(ib2,:);
            end
            slowCount = slowCount + 1;
            slowSegs(slowCount,:) = [pFar1(1) pFar1(2) pFar2(1) pFar2(2)];
        end

        layers{li} = [fastSegs; slowSegs(1:slowCount,:)];
    end
end
