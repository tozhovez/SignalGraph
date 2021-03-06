% compute log likelihood of featueres with a GMM model
% The parameters of the GMM is included as properties of the class and not
% updable. 
% For updatable parameters version, use GMMLogLikelihoodTunableNode. 
classdef GMMLogLikelihoodNode < GraphNodeCost
    properties
        prior;
        mu;
        invCov;
        diagCov;
        nGaussian;
        gconst=[];
        post = [];
        projection = [];
    end
    methods
        function obj = GMMLogLikelihoodNode(costWeight)
            obj = obj@GraphNodeCost('GMMLogLikelihood', costWeight);
        end
        
        function obj = initialize(obj, prior, mu, invCov)
            obj.prior = prior;
            obj.mu = mu;
            obj.invCov = invCov;
            [d1,d2,d3] = size(obj.invCov);
            obj.nGaussian = length(obj.prior);
            if obj.nGaussian==1
                obj.diagCov = d2==1;
            else
                obj.diagCov = d3==1;
            end
        end
        function obj = forward(obj,prev_layers)
            obj = obj.preprocessingForward(prev_layers);
            input = prev_layers{1}.a;
            [D(1),D(2),D(3),D(4)] = size(input);
            input = input(:,:);
            
            if isempty(obj.post)
                if isempty(obj.projection)
                    [~, obj.post] = compLikelihoodGMMFast(input, obj.gconst, obj.prior, obj.mu, obj.invCov, obj.diagCov);
                else
                    [~, obj.post] = compLikelihoodGMMFast(input, obj.gconst, obj.prior, obj.mu, obj.invCov, obj.diagCov, obj.projection);
                end
            end
            
            % output is the EM auxiliary function
            
            if obj.diagCov
                if 0    % for loop version
                    Z_sigma_Z = 0;
                    Z_sigma_mu = 0;
                    for t=1:nFr
                        for j=1:obj.nGaussian
                            Z_sigma_Z = Z_sigma_Z + obj.post(j,t) * sum( input(:,t).^2 .* obj.invCov(:,j) );
                            Z_sigma_mu = Z_sigma_mu + obj.post(j,t) * sum( input(:,t) .* obj.invCov(:,j) .* obj.mu(:,j) );
                        end
                    end
                else    % vectorized version
                    Z_sigma_Z = sum(sum(   obj.invCov'      * input.^2 .* obj.post ));
                    Z_sigma_mu = sum(sum( (obj.invCov.*obj.mu)' * input.* obj.post ));
                end
            else
                if 0    % for loop version
                    Z_sigma_Z2 = 0;
                    Z_sigma_mu2 = 0;
                    for t=1:nFr
                        for j=1:obj.nGaussian
                            Z_sigma_Z2 = Z_sigma_Z2 + obj.post(j,t) * input(:,t)' * obj.invCov(:,:,j) * input(:,t);
                            Z_sigma_mu2 = Z_sigma_mu2 + obj.post(j,t) * input(:,t)' * obj.invCov(:,:,j) * obj.mu(:,j);
                        end
                    end
                end
                
                if isempty(obj.projection)
                    obj.projection = obj.AllocateMemoryLike([dim*obj.nGaussian, dim], obj.invCov);
                    for i=1:obj.nGaussian
                        obj.projection((i-1)*dim+1:i*dim,:) = chol(obj.invCov(:,:,i));
                    end
                end
                
                data_proj = obj.projection * input;
                data_proj = reshape(data_proj, dim, obj.nGaussian, nFr);
                Z_sigma_Z =  sum(sum( squeeze(sum(data_proj.^2)) .* obj.post ));
                
                mu_proj = obj.projection * obj.mu;
                mu_proj = reshape(mu_proj, dim, obj.nGaussian, obj.nGaussian);
                for i=1:obj.nGaussian
                    mu_proj2(:,i) = mu_proj(:,i,i);
                end
                
                Z_sigma_mu = sum(sum( squeeze(sum(bsxfun(@times, data_proj, mu_proj2))) .* obj.post ));
            end
            
            % GaussianOccupation = sum(post,2)';
            % mu_sigma_mu = sum( GaussianOccupation .* sum( mu.^2 .* invCov ) );
            % norm_term   = sum( GaussianOccupation .* sum(log(invCov)) ) - dim * log(2*pi)*nFr;
            output = Z_sigma_Z/2 - Z_sigma_mu;% + mu_sigma_mu/2 + norm_term/2;
            obj.a = output / nFr;   % we actually minimize negative likelihood
            obj.a = reshape(obj.a, [1 D(2:end)]);
            
            obj = forward@GraphNodeCost(prev_layers);
        end
        
        function obj = backward(obj,future_layers, prev_layers)
            input = prev_layers{1}.a;
            [D(1),D(2),D(3),D(4)] = size(input);
            
            if obj.diagCov
                if 0   % for loop version
                    z_sigma = obj.AllocateMemoryLike(D, input);
                    mu_sigma = z_sigma;
                    for t=1:nFr
                        for j=1:obj.nGaussian
                            z_sigma(:,t) = z_sigma(:,t) + obj.post(j,t) * input(:,t) .* obj.invCov(:,j);
                            mu_sigma(:,t) = mu_sigma(:,t) + obj.post(j,t) * obj.mu(:,j) .* obj.invCov(:,j);
                        end
                    end
                else    % vectorized version
                    z_sigma = bsxfun(@times, input, reshape(obj.invCov,dim,1,obj.nGaussian));
                    z_sigma = bsxfun(@times, z_sigma, reshape(obj.post', 1, nFr,obj.nGaussian));
                    %         z_sigma2 = bsxfun(@times, input, permute(invCov,[1 3 2]));
                    %         z_sigma2 = bsxfun(@times, z_sigma2, permute(post', [3 1 2]));
                    
                    z_sigma = squeeze(sum(z_sigma,3));
                    mu_sigma = (obj.mu.*obj.invCov) * obj.post;
                end
            else
                if 0    % for loop version
                    z_sigma2 = obj.AllocateMemoryLike(D, input);
                    mu_sigma2 = z_sigma2;
                    for t=1:nFr
                        for j=1:obj.nGaussian
                            z_sigma2(:,t) = z_sigma2(:,t) + obj.post(j,t) * obj.invCov(:,:,j) * input(:,t);
                            mu_sigma2(:,t) = mu_sigma2(:,t) + obj.post(j,t) * obj.invCov(:,:,j) * obj.mu(:,j);
                        end
                    end
                end
                
                projection = reshape(obj.invCov, dim, dim*obj.nGaussian)';
                data_proj = projection * input;
                data_proj = reshape(data_proj, dim, obj.nGaussian, nFr);
                
                z_sigma =  bsxfun(@times, data_proj, permute(obj.post, [3 1 2]));
                z_sigma = squeeze(sum(z_sigma,2));
                
                mu_proj = projection * obj.mu;
                mu_proj = reshape(mu_proj, dim, obj.nGaussian, obj.nGaussian);
                for i=1:obj.nGaussian
                    mu_proj2(:,i) = mu_proj(:,i,i);
                end
                mu_sigma = mu_proj2 * obj.post;
            end
            
            obj.grad{1} = -mu_sigma + z_sigma;
            obj.grad{1} = obj.grad{1} / prod(D(2:end));
            obj.grad{1} = reshape(obj.grad{1}, D);
            
            obj = backward@GraphNodeCost(obj, prev_layers, future_layers);
        end
        
    end
    
end