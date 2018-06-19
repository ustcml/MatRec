function [B,D] = bccf(R, varargin)
[opt.lambda, max_iter, k, test, debug] = process_options(varargin, 'lambda', 0.01, 'max_iter', 10, 'K', 20, 'test', [], 'debug',true);
fprintf('bccf (K=%d, max_iter=%d, lambda=%f)\n', k, max_iter, opt.lambda);
[m,n] = size(R);
[I,J,V]=find(R);
V = (V - min(V)) ./ (max(V) - min(V));
R = sparse(I,J,V,m,n);
Rt = R';
rng(200);
B = randn(m,k)*0.1; D = randn(n,k)*0.1;
converge = false;
it = 1;
loss0 = 0;
while ~converge
    B = optimize_(Rt, D, B, opt);
    D = optimize_(R, B, D, opt);
    loss = loss_();
    if debug
        fprintf('Iteration=%3d of all optimization, loss=%.1f,', it, loss);
        if ~isempty(test)
            metric = evaluate_rating(test, B, D, 10);
            fprintf('ndcg@1=%.3f', metric.ndcg(1));
        end
        fprintf('\n')
    end
    if it >= max_iter || abs(loss0-loss)<1e-4 * loss || abs(loss0-loss)<1
        converge = true;
    end
    it = it + 1;
    loss0 = loss;
end
[B,D]=itq(B,D);
function v = loss_()
    [r_idx, c_idx, r] = find(R);
    r_ = sum(B(r_idx,:) .* D(c_idx,:),2);
    v = sum((r - 1/2 - r_/(2*k)).^2);
    v = v + opt.lambda * norm(sum(B))^2;
    v = v + opt.lambda * norm(sum(D))^2;
end

end

function B = optimize_(Rt, D, B, opt)
m = size(Rt, 2);
k = size(D,2);
opt.bsum = sum(B)';
for u=1:m
    r = Rt(:,u);
    b = B(u,:)';
    idx = r~=0;
    Du = D(idx,:);
    ru = (full(r(idx)) - 1/2);
    %opt.H = 1/(2*k^2) * (Du' * Du);
    opt.g = @(x) 1/(2*k^2) * (Du' * (Du * x)) - Du' * (ru / k);
    opt.f = @(x) sum((ru - Du * x / (2*k)).^2);
    hfun = @(Hinfo,Y) Hinfo*Y - 1/(2*k^2) * (Du' * (Du * Y));
    opt.bsum = opt.bsum - b;
    options = optimoptions('fmincon','Algorithm','trust-region-reflective', ...
        'SpecifyObjectiveGradient',true,'HessianMultiplyFcn',hfun,'Display','off');
    b1 = fmincon(@(x) fun(x,opt), b, [], [], [], [], -ones(k,1), ones(k,1),[], options);
    %options = optimoptions('fminunc','Algorithm','trust-region', ...
    %    'SpecifyObjectiveGradient',true,'HessianFcn','objective','Display','off','MaxIterations',20);
    %b1 = fminunc(@(x) fun(x,opt), b, options);
    opt.bsum = opt.bsum + b1;
    B(u,:) = b1;
end
end

function [f,g,H] = fun(b, opt)
% d: kx1 vector
    k = length(b);
    f = opt.lambda * norm(opt.bsum + b)^2  + opt.f(b);
    g = opt.lambda * 2 * (opt.bsum + b) + opt.g(b);
    H = opt.lambda * 2 ;%* speye(k); %+ opt.H;
end
function [B1,D1] = itq(B,D)
[B1,D1]=rounding(B,D);
converge = false;
loss0=inf;
while ~converge
    Q = proj_stiefel_manifold(B'*B1+D'*D1);
    [B1,D1] = rounding(B*Q, D*Q);
    loss1 = loss_();
    if(abs(loss1-loss0)<1e-6*loss1 || loss1>loss0)
        converge = true;
    end
    %fprintf('%f\n',loss1);
    loss0 = loss1;
end
function v=loss_()
    v = norm(B1-B*Q, 'fro')^2 + norm(D1-D*Q, 'fro')^2;
end
end
function [B1,D1] = rounding(B,D)
B1 = bsxfun(@gt, B, median(B));
B1 = 2*B1 - 1;
D1 = bsxfun(@gt, D, median(D));
D1 = 2*D1 - 1;
end

